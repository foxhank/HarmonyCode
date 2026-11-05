import { AgentLimits } from '../agent/AgentLimits';
import { CancelToken } from '../llm/CancelToken';
import { Json, JsonObject } from '../llm/Json';
import { PathUtil } from '../fs/PathUtil';
import { SftpAttrs, SftpClient, SftpEntry } from './ssh/SftpClient';

/** A file found by walking one side. `rel` uses '/' and is relative to that side's root. */
export interface SyncFile {
  rel: string;
  size: number;
  /** Seconds since the epoch. */
  mtime: number;
}

/** The phone side of a sync: the project folder. */
export interface SyncLocalFs {
  /** Every file under `root`, not descending into folders `skip` returns true for. */
  walk(root: string, skip: (name: string) => boolean): Promise<SyncFile[]>;
  stat(path: string): Promise<SyncFile | null>;
  read(path: string): Promise<Uint8Array>;
  /** Creates parent folders. */
  write(path: string, data: Uint8Array): Promise<void>;
  remove(path: string): Promise<void>;
}

/** Where the record of the last sync is kept between runs. */
export interface ManifestStore {
  load(): string;
  save(text: string): void;
}

/** What one sync did. */
export class SyncReport {
  uploaded: string[] = [];
  downloaded: string[] = [];
  deletedLocal: string[] = [];
  deletedRemote: string[] = [];
  /** Changed on both sides: the phone's version won; the computer's is saved as `<file>.conflict`. */
  conflicts: string[] = [];
  /** Too large to sync. */
  skipped: string[] = [];

  get changedLocally(): string[] {
    return this.downloaded.concat(this.deletedLocal);
  }

  get total(): number {
    return this.uploaded.length + this.downloaded.length + this.deletedLocal.length + this.deletedRemote.length +
      this.conflicts.length;
  }

  /** One line for the agent and the UI, '' when nothing happened. */
  summary(): string {
    const parts: string[] = [];
    const add = (n: number, what: string): void => {
      if (n > 0) {
        parts.push(`${n} ${what}`);
      }
    };
    add(this.uploaded.length, 'uploaded');
    add(this.downloaded.length, 'downloaded');
    add(this.deletedRemote.length, 'deleted on the computer');
    add(this.deletedLocal.length, 'deleted on the phone');
    add(this.conflicts.length, 'conflicts');
    add(this.skipped.length, 'too large, skipped');
    return parts.join(', ');
  }
}

/** State of one file at the last sync, on both sides. */
interface Entry {
  lsize: number;
  lmtime: number;
  rsize: number;
  rmtime: number;
}

/** Files larger than this are not synced. */
const MAX_FILE_BYTES: number = 64 * 1024 * 1024;
export const CONFLICT_SUFFIX: string = '.conflict';
const MANIFEST_VERSION: number = 1;

/**
 * Two-way sync between a project folder on the phone and a folder on a remote computer, over SFTP.
 * A manifest of what both sides looked like at the last sync tells edits from deletions on either
 * side. When a file changed on both sides, the phone's version wins and the computer's version is
 * kept next to it as `<file>.conflict`. Dependency and build folders are never synced.
 */
export class ProjectSync {
  private local: SyncLocalFs;
  private localRoot: string;
  private remoteRoot: string;
  private store: ManifestStore;
  private running: Promise<SyncReport> | null = null;

  constructor(local: SyncLocalFs, localRoot: string, remoteRoot: string, store: ManifestStore) {
    this.local = local;
    this.localRoot = localRoot;
    this.remoteRoot = remoteRoot;
    this.store = store;
  }

  get remoteDir(): string {
    return this.remoteRoot;
  }

  /** Folders never synced (dependencies, build output, VCS internals, conflict copies are files). */
  static skipDir(name: string): boolean {
    return AgentLimits.IGNORED_DIRS.indexOf(name) >= 0;
  }

  /** Remote path for a phone path inside the project ('' when outside). */
  toRemote(localPath: string): string {
    if (!PathUtil.isInside(this.localRoot, localPath)) {
      return '';
    }
    const rel = PathUtil.relative(this.localRoot, localPath);
    return rel.length === 0 ? this.remoteRoot : PathUtil.join(this.remoteRoot, rel);
  }

  /** Runs one sync; concurrent callers share the one in progress. */
  sync(sftp: SftpClient, cancel: CancelToken): Promise<SyncReport> {
    if (this.running !== null) {
      return this.running;
    }
    const p = this.run(sftp, cancel).finally(() => {
      this.running = null;
    });
    this.running = p;
    return p;
  }

  private async run(sftp: SftpClient, cancel: CancelToken): Promise<SyncReport> {
    const report = new SyncReport();
    const manifest = this.loadManifest();
    await ProjectSync.mkdirs(sftp, this.remoteRoot);
    const localFiles = await this.local.walk(this.localRoot, (n: string) => ProjectSync.skipDir(n));
    const remoteFiles = await ProjectSync.walkRemote(sftp, this.remoteRoot, '', cancel);
    const L: Map<string, SyncFile> = new Map();
    const R: Map<string, SyncFile> = new Map();
    for (const f of localFiles) {
      L.set(f.rel, f);
    }
    for (const f of remoteFiles) {
      R.set(f.rel, f);
    }
    const all: Set<string> = new Set();
    for (const k of L.keys()) {
      all.add(k);
    }
    for (const k of R.keys()) {
      all.add(k);
    }
    for (const k of manifest.keys()) {
      all.add(k);
    }
    const next: Map<string, Entry> = new Map();
    for (const rel of Array.from(all).sort()) {
      cancel.throwIfCancelled();
      const l = L.get(rel);
      const r = R.get(rel);
      const m = manifest.get(rel);
      const lChanged = l !== undefined && (m === undefined || l.size !== m.lsize || l.mtime !== m.lmtime);
      const rChanged = r !== undefined && (m === undefined || r.size !== m.rsize || r.mtime !== m.rmtime);
      if ((l !== undefined && l.size > MAX_FILE_BYTES) || (r !== undefined && r.size > MAX_FILE_BYTES)) {
        report.skipped.push(rel);
        if (m !== undefined) {
          next.set(rel, m);
        }
        continue;
      }
      if (l !== undefined && r === undefined) {
        if (m !== undefined && !lChanged) {
          await this.local.remove(this.localPath(rel));
          report.deletedLocal.push(rel);
        } else {
          next.set(rel, await this.upload(sftp, rel));
          report.uploaded.push(rel);
        }
      } else if (l === undefined && r !== undefined) {
        if (m !== undefined && !rChanged) {
          await sftp.remove(this.remotePath(rel));
          report.deletedRemote.push(rel);
        } else {
          next.set(rel, await this.download(sftp, rel));
          report.downloaded.push(rel);
        }
      } else if (l !== undefined && r !== undefined) {
        if (!lChanged && !rChanged) {
          next.set(rel, m as Entry);
        } else if (lChanged && !rChanged && m !== undefined) {
          next.set(rel, await this.upload(sftp, rel));
          report.uploaded.push(rel);
        } else if (!lChanged && rChanged) {
          next.set(rel, await this.download(sftp, rel));
          report.downloaded.push(rel);
        } else {
          next.set(rel, await this.resolveBoth(sftp, rel, report));
        }
      }
      // Gone on both sides: forget it.
    }
    this.saveManifest(next);
    return report;
  }

  /** Both sides have the file and at least one changed it (or it was never synced). */
  private async resolveBoth(sftp: SftpClient, rel: string, report: SyncReport): Promise<Entry> {
    const mine = await this.local.read(this.localPath(rel));
    const theirs = await sftp.readFile(this.remotePath(rel), MAX_FILE_BYTES);
    if (ProjectSync.same(mine, theirs)) {
      return this.entry(sftp, rel);
    }
    await this.local.write(this.localPath(rel + CONFLICT_SUFFIX), theirs);
    report.conflicts.push(rel);
    return this.upload(sftp, rel);
  }

  private async upload(sftp: SftpClient, rel: string): Promise<Entry> {
    const target = this.remotePath(rel);
    await ProjectSync.mkdirs(sftp, PathUtil.dirName(target));
    await sftp.writeFile(target, await this.local.read(this.localPath(rel)));
    return this.entry(sftp, rel);
  }

  private async download(sftp: SftpClient, rel: string): Promise<Entry> {
    await this.local.write(this.localPath(rel), await sftp.readFile(this.remotePath(rel), MAX_FILE_BYTES));
    return this.entry(sftp, rel);
  }

  /** Both sides' current state of a file that is now in sync. */
  private async entry(sftp: SftpClient, rel: string): Promise<Entry> {
    const l = await this.local.stat(this.localPath(rel));
    const r: SftpAttrs = await sftp.stat(this.remotePath(rel));
    return {
      lsize: l !== null ? l.size : -1, lmtime: l !== null ? l.mtime : -1, rsize: r.size, rmtime: r.mtime
    };
  }

  private localPath(rel: string): string {
    return PathUtil.join(this.localRoot, rel);
  }

  private remotePath(rel: string): string {
    return PathUtil.join(this.remoteRoot, rel);
  }

  private static same(a: Uint8Array, b: Uint8Array): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }

  private static async walkRemote(sftp: SftpClient, root: string, rel: string, cancel: CancelToken): Promise<SyncFile[]> {
    cancel.throwIfCancelled();
    const dir = rel.length > 0 ? PathUtil.join(root, rel) : root;
    let entries: SftpEntry[] = [];
    try {
      entries = await sftp.list(dir);
    } catch (e) {
      return [];
    }
    const out: SyncFile[] = [];
    for (const e of entries) {
      const childRel = rel.length > 0 ? rel + '/' + e.name : e.name;
      if (e.attrs.isDir) {
        if (!ProjectSync.skipDir(e.name)) {
          for (const f of await ProjectSync.walkRemote(sftp, root, childRel, cancel)) {
            out.push(f);
          }
        }
      } else if (!e.attrs.isLink) {
        out.push({ rel: childRel, size: e.attrs.size, mtime: e.attrs.mtime });
      }
    }
    return out;
  }

  private static async mkdirs(sftp: SftpClient, path: string): Promise<void> {
    const missing: string[] = [];
    let p = path;
    while (p.length > 1 && !new RegExp('^/[A-Za-z]:/?$').test(p)) {
      const st = await sftp.statOrNull(p);
      if (st !== null) {
        break;
      }
      missing.unshift(p);
      p = PathUtil.dirName(p);
    }
    for (const m of missing) {
      await sftp.mkdir(m);
    }
  }

  private loadManifest(): Map<string, Entry> {
    const out: Map<string, Entry> = new Map();
    const o = Json.parseObject(this.store.load());
    if (o === null || Json.num(o, 'version') !== MANIFEST_VERSION || Json.str(o, 'remote') !== this.remoteRoot) {
      return out;
    }
    const files = Json.obj(o, 'files');
    if (files === null) {
      return out;
    }
    for (const k of Object.keys(files)) {
      const e = Json.asObject(files[k]);
      out.set(k, {
        lsize: Json.num(e, 'lsize', -1), lmtime: Json.num(e, 'lmtime', -1),
        rsize: Json.num(e, 'rsize', -1), rmtime: Json.num(e, 'rmtime', -1)
      });
    }
    return out;
  }

  private saveManifest(m: Map<string, Entry>): void {
    const files: JsonObject = {};
    for (const k of m.keys()) {
      const e = m.get(k) as Entry;
      const o: JsonObject = { 'lsize': e.lsize, 'lmtime': e.lmtime, 'rsize': e.rsize, 'rmtime': e.rmtime };
      files[k] = o;
    }
    const doc: JsonObject = { 'version': MANIFEST_VERSION, 'remote': this.remoteRoot, 'files': files };
    this.store.save(JSON.stringify(doc));
  }
}
