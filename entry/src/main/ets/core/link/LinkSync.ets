import { Json, JsonObject } from '../llm/Json';
import { PathUtil } from '../fs/PathUtil';
import { ManifestStore, ProjectSync, SyncFile, SyncLocalFs, SyncReport, CONFLICT_SUFFIX } from '../remote/ProjectSync';
import { Bytes } from '../remote/ssh/Bytes';
import { HashAlg, SshCrypto } from '../remote/ssh/SshCrypto';
import { LinkClient, LinkResult } from './LinkClient';
import { LinkEntry, LinkStatus, ZERO_HASH } from './LinkProtocol';

const STATE_VERSION: number = 1;
/** Rounds of re-deciding after the desktop changed a file mid-sync. */
const MAX_ROUNDS: number = 3;

interface CacheEntry {
  size: number;
  mtime: number;
  hash: string;
}

/**
 * The phone side of Link sync (docs/desktop-link.md section 7). Keeps the base (last agreed hash
 * per file) and a hash cache of the phone's files; the desktop's state comes from LIST and CHANGED.
 * Decides each file exactly; writes to the desktop are compare-and-swap, so races resolve safely.
 */
export class LinkSync {
  private local: SyncLocalFs;
  private root: string;
  private prefix: string;
  private crypto: SshCrypto;
  private store: ManifestStore;
  private base: Map<string, string> = new Map();
  private cache: Map<string, CacheEntry> = new Map();
  /** The desktop's files under the prefix, by project-relative path (hex hashes). */
  private remote: Map<string, LinkEntry> = new Map();
  private haveRemote: boolean = false;
  private running: Promise<SyncReport> | null = null;
  private again: boolean = false;

  constructor(local: SyncLocalFs, localRoot: string, prefix: string, crypto: SshCrypto, store: ManifestStore) {
    this.local = local;
    this.root = localRoot;
    this.prefix = prefix.replace(new RegExp('^/+|/+$', 'g'), '');
    this.crypto = crypto;
    this.store = store;
    this.load();
  }

  get desktopFolder(): string {
    return this.prefix;
  }

  /** Desktop path (workspace-relative) for a phone path inside the project; '' when outside. */
  toDesktop(localPath: string): string {
    if (!PathUtil.isInside(this.root, localPath)) {
      return '';
    }
    const rel = PathUtil.relative(this.root, localPath);
    return this.join(rel);
  }

  /** Applies a CHANGED event. Returns true when it concerns this project. */
  applyEvent(entries: LinkEntry[]): boolean {
    let mine = false;
    for (const e of entries) {
      const rel = this.relOf(e.path);
      if (rel.length === 0 || LinkSync.skipped(rel)) {
        continue;
      }
      mine = true;
      if (e.deleted) {
        this.remote.delete(rel);
      } else {
        this.remote.set(rel, e);
      }
    }
    return mine;
  }

  /** Brings both sides in line. `refresh` re-lists the desktop first. Concurrent calls coalesce. */
  sync(client: LinkClient, refresh: boolean): Promise<SyncReport> {
    if (this.running !== null) {
      this.again = true;
      return this.running;
    }
    const p = this.loop(client, refresh).finally(() => {
      this.running = null;
    });
    this.running = p;
    return p;
  }

  private async loop(client: LinkClient, refresh: boolean): Promise<SyncReport> {
    const report = new SyncReport();
    let list = refresh || !this.haveRemote;
    for (let round = 0; round < MAX_ROUNDS; round++) {
      this.again = false;
      if (list) {
        await this.listRemote(client);
      }
      const retry = await this.reconcile(client, report);
      this.save();
      if (!retry && !this.again) {
        break;
      }
      list = retry;
    }
    return report;
  }

  private async listRemote(client: LinkClient): Promise<void> {
    const entries = await client.list(this.prefix);
    this.remote.clear();
    for (const e of entries) {
      const rel = this.relOf(e.path);
      if (rel.length > 0 && !LinkSync.skipped(rel) && !e.deleted) {
        this.remote.set(rel, e);
      }
    }
    this.haveRemote = true;
  }

  /** One pass over every path. Returns true when the desktop changed underneath and a re-list is needed. */
  private async reconcile(client: LinkClient, report: SyncReport): Promise<boolean> {
    const files = await this.local.walk(this.root, (n: string) => ProjectSync.skipDir(n));
    const phone: Map<string, SyncFile> = new Map();
    for (const f of files) {
      phone.set(f.rel, f);
    }
    const all: Set<string> = new Set();
    for (const k of phone.keys()) {
      all.add(k);
    }
    for (const k of this.remote.keys()) {
      all.add(k);
    }
    for (const k of this.base.keys()) {
      all.add(k);
    }
    let retry = false;
    for (const rel of Array.from(all).sort()) {
      const f = phone.get(rel);
      const P = f !== undefined ? await this.localHash(rel, f) : '';
      const e = this.remote.get(rel);
      const D = e !== undefined ? Bytes.hex(e.hash) : '';
      const B = this.base.get(rel) ?? '';
      if (P === D) {
        this.setBase(rel, P);
      } else if (D === B) {
        // Only the phone changed.
        const r = P.length === 0 ? await client.remove(this.join(rel), LinkSync.raw(B)) :
          await client.put(this.join(rel), LinkSync.raw(B), await this.local.read(this.localPath(rel)));
        if (this.settle(rel, r, P)) {
          if (P.length === 0) {
            report.deletedRemote.push(rel);
          } else {
            report.uploaded.push(rel);
          }
        } else {
          retry = true;
        }
      } else if (P === B) {
        // Only the desktop changed.
        if (D.length === 0) {
          await this.local.remove(this.localPath(rel));
          this.cache.delete(rel);
          report.deletedLocal.push(rel);
        } else {
          await this.download(client, rel, rel);
          report.downloaded.push(rel);
        }
        this.setBase(rel, D);
      } else if (P.length === 0) {
        // Deleted on the phone, edited on the desktop: keep the edit.
        await this.download(client, rel, rel);
        this.setBase(rel, D);
        report.downloaded.push(rel);
      } else {
        // Edited on the phone and edited or deleted on the desktop: the phone's version wins; a
        // desktop edit is kept beside it as <file>.conflict.
        if (D.length > 0) {
          await this.download(client, rel, rel + CONFLICT_SUFFIX);
        }
        const r = await client.put(this.join(rel), LinkSync.raw(D), await this.local.read(this.localPath(rel)));
        if (!this.settle(rel, r, P)) {
          retry = true;
          continue;
        }
        if (D.length > 0) {
          report.conflicts.push(rel);
        } else {
          report.uploaded.push(rel);
        }
      }
    }
    return retry;
  }

  /** Records a successful write; on a conflict remembers the desktop's new state. Returns success. */
  private settle(rel: string, r: LinkResult, phoneHash: string): boolean {
    if (r.status === LinkStatus.OK) {
      this.setBase(rel, phoneHash);
      if (phoneHash.length === 0) {
        this.remote.delete(rel);
      } else {
        const prev = this.remote.get(rel);
        this.remote.set(rel, { path: this.join(rel), size: prev !== undefined ? prev.size : 0, mtime: Date.now(),
          hash: r.hash, deleted: false });
      }
      return true;
    }
    if (r.status === LinkStatus.CONFLICT) {
      return false;
    }
    throw new Error(`The desktop refused ${rel}: ${LinkClient.statusText(r)}`);
  }

  private async download(client: LinkClient, rel: string, targetRel: string): Promise<void> {
    const data = await client.get(this.join(rel));
    await this.local.write(this.localPath(targetRel), data);
    const st = await this.local.stat(this.localPath(targetRel));
    if (st !== null && targetRel === rel) {
      this.cache.set(rel, { size: st.size, mtime: st.mtime, hash: Bytes.hex(this.crypto.hash(HashAlg.SHA256, data)) });
    }
  }

  private async localHash(rel: string, f: SyncFile): Promise<string> {
    const c = this.cache.get(rel);
    if (c !== undefined && c.size === f.size && c.mtime === f.mtime) {
      return c.hash;
    }
    const h = Bytes.hex(this.crypto.hash(HashAlg.SHA256, await this.local.read(this.localPath(rel))));
    this.cache.set(rel, { size: f.size, mtime: f.mtime, hash: h });
    return h;
  }

  private setBase(rel: string, hash: string): void {
    if (hash.length === 0) {
      this.base.delete(rel);
      this.cache.delete(rel);
    } else {
      this.base.set(rel, hash);
    }
  }

  private static raw(hex: string): Uint8Array {
    return hex.length === 0 ? ZERO_HASH : Bytes.fromHex(hex);
  }

  private static skipped(rel: string): boolean {
    return rel.split('/').some((seg: string, i: number, all: string[]) => i < all.length - 1 && ProjectSync.skipDir(seg));
  }

  private join(rel: string): string {
    return this.prefix.length > 0 ? (rel.length > 0 ? this.prefix + '/' + rel : this.prefix) : rel;
  }

  /** Project-relative path of a desktop path ('' when it is not in this project). */
  private relOf(path: string): string {
    if (this.prefix.length === 0) {
      return path;
    }
    return path.startsWith(this.prefix + '/') ? path.substring(this.prefix.length + 1) : '';
  }

  private localPath(rel: string): string {
    return PathUtil.join(this.root, rel);
  }

  private load(): void {
    const o = Json.parseObject(this.store.load());
    if (o === null || Json.num(o, 'version') !== STATE_VERSION || Json.str(o, 'prefix') !== this.prefix) {
      return;
    }
    const base = Json.obj(o, 'base');
    if (base !== null) {
      for (const k of Object.keys(base)) {
        this.base.set(k, Json.str(base, k));
      }
    }
    const cache = Json.obj(o, 'cache');
    if (cache !== null) {
      for (const k of Object.keys(cache)) {
        const c = Json.asObject(cache[k]);
        this.cache.set(k, { size: Json.num(c, 'size', -1), mtime: Json.num(c, 'mtime', -1), hash: Json.str(c, 'hash') });
      }
    }
  }

  private save(): void {
    const base: JsonObject = {};
    for (const k of this.base.keys()) {
      base[k] = this.base.get(k) as string;
    }
    const cache: JsonObject = {};
    for (const k of this.cache.keys()) {
      const c = this.cache.get(k) as CacheEntry;
      const o: JsonObject = { 'size': c.size, 'mtime': c.mtime, 'hash': c.hash };
      cache[k] = o;
    }
    const doc: JsonObject = { 'version': STATE_VERSION, 'prefix': this.prefix, 'base': base, 'cache': cache };
    this.store.save(JSON.stringify(doc));
  }
}

