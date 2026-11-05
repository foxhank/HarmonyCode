// The phone side of a project sync over Node's fs (tests only).
import * as fs from 'fs';
import * as path from 'path';
import { ManifestStore, SyncFile, SyncLocalFs } from '../../entry/src/main/ets/core/remote/ProjectSync';

export class NodeSyncFs implements SyncLocalFs {
  async walk(root: string, skip: (n: string) => boolean): Promise<SyncFile[]> {
    const out: SyncFile[] = [];
    const visit = (dir: string, rel: string): void => {
      for (const name of fs.readdirSync(dir)) {
        const p = path.join(dir, name);
        const r = rel.length > 0 ? rel + '/' + name : name;
        const st = fs.statSync(p);
        if (st.isDirectory()) {
          if (!skip(name)) {
            visit(p, r);
          }
        } else {
          out.push({ rel: r, size: st.size, mtime: Math.floor(st.mtimeMs / 1000) });
        }
      }
    };
    visit(root, '');
    return out;
  }

  async stat(p: string): Promise<SyncFile | null> {
    try {
      const st = fs.statSync(p);
      return { rel: '', size: st.size, mtime: Math.floor(st.mtimeMs / 1000) };
    } catch (e) {
      return null;
    }
  }

  async read(p: string): Promise<Uint8Array> {
    return new Uint8Array(fs.readFileSync(p));
  }

  async write(p: string, data: Uint8Array): Promise<void> {
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, data);
  }

  async remove(p: string): Promise<void> {
    fs.rmSync(p, { force: true });
  }
}

export class MemoryStore implements ManifestStore {
  text = '';
  load(): string {
    return this.text;
  }
  save(t: string): void {
    this.text = t;
  }
}
