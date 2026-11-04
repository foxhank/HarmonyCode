import { AgentFs, FsEntry, FsStat, sortEntries } from '../agent/AgentFs';
import { PathUtil } from '../fs/PathUtil';
import { Utf8 } from './ssh/Bytes';
import { SftpClient, SftpEntry, SftpError, SftpStatus } from './ssh/SftpClient';
import { RemoteConnection } from './RemoteConnection';

/** Largest text file read over SFTP. */
const MAX_TEXT_BYTES: number = 8 * 1024 * 1024;
const BINARY_SNIFF: number = 8000;

/** AgentFs over SFTP on a remote computer. Paths are in SFTP form ("/home/dev", "/C:/Users/dev"). */
export class RemoteFs implements AgentFs {
  private conn: RemoteConnection;

  constructor(conn: RemoteConnection) {
    this.conn = conn;
  }

  async stat(path: string): Promise<FsStat | null> {
    const a = await (await this.conn.sftp()).statOrNull(path);
    return a === null ? null : { isDir: a.isDir, size: a.isDir ? 0 : Math.max(0, a.size) };
  }

  async list(dir: string): Promise<FsEntry[]> {
    const sftp = await this.conn.sftp();
    const out: FsEntry[] = [];
    for (const e of await sftp.list(dir)) {
      if (e.name === '.git') {
        continue;
      }
      const path = PathUtil.join(dir, e.name);
      let isDir = e.attrs.isDir;
      let size = e.attrs.size;
      if (e.attrs.isLink) {
        // Listings describe links themselves; follow them to see what they point at.
        const target = await sftp.statOrNull(path);
        isDir = target !== null && target.isDir;
        size = target !== null ? target.size : 0;
      }
      out.push({ name: e.name, path: path, isDir: isDir, size: isDir ? 0 : Math.max(0, size) });
    }
    return sortEntries(out);
  }

  async readText(path: string): Promise<string> {
    const data = await (await this.conn.sftp()).readFile(path, MAX_TEXT_BYTES);
    const n = Math.min(data.length, BINARY_SNIFF);
    for (let i = 0; i < n; i++) {
      if (data[i] === 0) {
        throw new Error(PathUtil.baseName(path) + ' is a binary file.');
      }
    }
    return Utf8.decode(data);
  }

  async writeText(path: string, text: string): Promise<void> {
    await this.mkdirs(PathUtil.dirName(path));
    await (await this.conn.sftp()).writeFile(path, Utf8.encode(text));
  }

  async remove(path: string): Promise<void> {
    const sftp = await this.conn.sftp();
    await RemoteFs.removeTree(sftp, path);
  }

  async mkdirs(path: string): Promise<void> {
    const sftp = await this.conn.sftp();
    const missing: string[] = [];
    let p = path;
    while (p.length > 1 && !RemoteFs.isDriveRoot(p)) {
      const st = await sftp.statOrNull(p);
      if (st !== null) {
        if (!st.isDir) {
          throw new Error(p + ' exists and is not a folder.');
        }
        break;
      }
      missing.unshift(p);
      p = PathUtil.dirName(p);
    }
    for (const m of missing) {
      await sftp.mkdir(m);
    }
  }

  async rename(from: string, to: string): Promise<void> {
    const sftp = await this.conn.sftp();
    try {
      await sftp.rename(from, to);
    } catch (e) {
      // Plain SFTP rename refuses to replace; servers without posix-rename need the target gone first.
      const target = await sftp.statOrNull(to);
      if (target === null || target.isDir) {
        throw e as Error;
      }
      await sftp.remove(to);
      await sftp.rename(from, to);
    }
  }

  private static isDriveRoot(p: string): boolean {
    return new RegExp('^/[A-Za-z]:/?$').test(p);
  }

  private static async removeTree(sftp: SftpClient, path: string): Promise<void> {
    const st = await sftp.lstat(path).catch((e: Error) => {
      if (e instanceof SftpError && (e as SftpError).code === SftpStatus.NO_SUCH_FILE) {
        return null;
      }
      throw e;
    });
    if (st === null) {
      return;
    }
    if (st.isDir && !st.isLink) {
      const entries: SftpEntry[] = await sftp.list(path);
      for (const e of entries) {
        await RemoteFs.removeTree(sftp, PathUtil.join(path, e.name));
      }
      await sftp.rmdir(path);
    } else {
      await sftp.remove(path);
    }
  }
}
