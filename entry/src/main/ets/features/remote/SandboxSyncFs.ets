import { fileIo } from '@kit.CoreFileKit';
import { FileService } from '../../core/fs/FileService';
import { PathUtil } from '../../core/fs/PathUtil';
import { ManifestStore, SyncFile, SyncLocalFs } from '../../core/remote/ProjectSync';

/** The phone side of a project sync: raw bytes in the app sandbox. */
export class SandboxSyncFs implements SyncLocalFs {
  async walk(root: string, skip: (name: string) => boolean): Promise<SyncFile[]> {
    const out: SyncFile[] = [];
    SandboxSyncFs.visit(root, '', skip, out);
    return out;
  }

  async stat(path: string): Promise<SyncFile | null> {
    try {
      const st = fileIo.statSync(path);
      return { rel: '', size: st.size, mtime: st.mtime };
    } catch (e) {
      return null;
    }
  }

  async read(path: string): Promise<Uint8Array> {
    const size = fileIo.statSync(path).size;
    const buf = new ArrayBuffer(size);
    const f = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      let off = 0;
      while (off < size) {
        const n = fileIo.readSync(f.fd, buf, { offset: off, length: size - off });
        if (n <= 0) {
          break;
        }
        off += n;
      }
    } finally {
      fileIo.closeSync(f);
    }
    return new Uint8Array(buf);
  }

  async write(path: string, data: Uint8Array): Promise<void> {
    FileService.mkdirs(PathUtil.dirName(path));
    const f = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      if (data.length > 0) {
        const copy = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength) as ArrayBuffer;
        fileIo.writeSync(f.fd, copy);
      }
    } finally {
      fileIo.closeSync(f);
    }
  }

  async remove(path: string): Promise<void> {
    if (FileService.exists(path)) {
      fileIo.unlinkSync(path);
    }
  }

  private static visit(dir: string, rel: string, skip: (name: string) => boolean, out: SyncFile[]): void {
    let names: string[] = [];
    try {
      names = fileIo.listFileSync(dir);
    } catch (e) {
      return;
    }
    for (const name of names) {
      const path = PathUtil.join(dir, name);
      const childRel = rel.length > 0 ? rel + '/' + name : name;
      let st: fileIo.Stat;
      try {
        st = fileIo.lstatSync(path);
      } catch (e) {
        continue;
      }
      if (st.isDirectory()) {
        if (!skip(name)) {
          SandboxSyncFs.visit(path, childRel, skip, out);
        }
      } else if (st.isFile()) {
        out.push({ rel: childRel, size: st.size, mtime: st.mtime });
      }
    }
  }
}

/** The sync record of one project and computer, kept outside the project folder. */
export class FileManifestStore implements ManifestStore {
  private path: string;

  constructor(path: string) {
    this.path = path;
  }

  load(): string {
    try {
      return FileService.exists(this.path) ? FileService.readText(this.path) : '';
    } catch (e) {
      return '';
    }
  }

  save(text: string): void {
    FileService.writeText(this.path, text);
  }
}
