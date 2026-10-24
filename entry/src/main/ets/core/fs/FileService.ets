import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppConfig } from '../common/AppConfig';
import { Strings } from '../common/Strings';
import { PathUtil } from './PathUtil';

export interface FileEntry {
  name: string;
  path: string;
  isDir: boolean;
}

/** Thin, synchronous wrapper over the sandbox file system. Throws localized errors. */
export class FileService {
  static exists(path: string): boolean {
    try {
      return fileIo.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  static isDir(path: string): boolean {
    try {
      return fileIo.statSync(path).isDirectory();
    } catch (e) {
      return false;
    }
  }

  static size(path: string): number {
    try {
      return fileIo.statSync(path).size;
    } catch (e) {
      return 0;
    }
  }

  /** Folders first, then files, case-insensitive. Hides `.git`. */
  static list(dir: string, showHidden: boolean = true): FileEntry[] {
    let names: string[] = [];
    try {
      names = fileIo.listFileSync(dir);
    } catch (e) {
      return [];
    }
    const out: FileEntry[] = [];
    for (const n of names) {
      if (n === '.git' || (!showHidden && n.startsWith('.'))) {
        continue;
      }
      const p = PathUtil.join(dir, n);
      out.push({ name: n, path: p, isDir: FileService.isDir(p) });
    }
    out.sort((a: FileEntry, b: FileEntry) => {
      if (a.isDir !== b.isDir) {
        return a.isDir ? -1 : 1;
      }
      return a.name.toLowerCase().localeCompare(b.name.toLowerCase());
    });
    return out;
  }

  static mkdirs(path: string): void {
    if (!FileService.exists(path)) {
      fileIo.mkdirSync(path, true);
    }
  }

  /** Reads UTF-8 text. Throws for binary or oversized files. */
  static readText(path: string): string {
    const size = FileService.size(path);
    if (size > AppConfig.MAX_TEXT_FILE_BYTES) {
      throw new Error(Strings.get('err_file_too_large', Math.round(size / 1024 / 1024)));
    }
    if (size === 0) {
      return '';
    }
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const buf = new ArrayBuffer(size);
      const n = fileIo.readSync(file.fd, buf);
      const bytes = new Uint8Array(buf, 0, n);
      const probe = Math.min(n, AppConfig.BINARY_PROBE_BYTES);
      for (let i = 0; i < probe; i++) {
        if (bytes[i] === 0) {
          throw new Error(Strings.get('err_binary_file'));
        }
      }
      return util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(bytes);
    } finally {
      fileIo.closeSync(file);
    }
  }

  static writeText(path: string, text: string): void {
    FileService.mkdirs(PathUtil.dirName(path));
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      if (text.length > 0) {
        fileIo.writeSync(file.fd, text);
      }
    } finally {
      fileIo.closeSync(file);
    }
  }

  static createFile(path: string): void {
    FileService.ensureFree(path);
    FileService.writeText(path, '');
  }

  static createDir(path: string): void {
    FileService.ensureFree(path);
    fileIo.mkdirSync(path, true);
  }

  static rename(from: string, to: string): void {
    FileService.ensureFree(to);
    fileIo.renameSync(from, to);
  }

  /** Deletes a file, or a folder with everything in it. */
  static remove(path: string): void {
    if (FileService.isDir(path)) {
      fileIo.rmdirSync(path);
    } else {
      fileIo.unlinkSync(path);
    }
  }

  static copy(from: string, to: string): void {
    FileService.ensureFree(to);
    if (FileService.isDir(from)) {
      fileIo.mkdirSync(to, true);
      for (const e of FileService.list(from)) {
        FileService.copy(e.path, PathUtil.join(to, e.name));
      }
    } else {
      fileIo.copyFileSync(from, to);
    }
  }

  /** All files under root (skipping AppConfig.IGNORED_DIRS), up to `limit`. */
  static walk(root: string, limit: number): string[] {
    const out: string[] = [];
    const stack: string[] = [root];
    while (stack.length > 0 && out.length < limit) {
      const dir = stack.pop() as string;
      let names: string[] = [];
      try {
        names = fileIo.listFileSync(dir);
      } catch (e) {
        continue;
      }
      for (const n of names) {
        const p = PathUtil.join(dir, n);
        if (FileService.isDir(p)) {
          if (AppConfig.IGNORED_DIRS.indexOf(n) < 0) {
            stack.push(p);
          }
        } else {
          out.push(p);
          if (out.length >= limit) {
            break;
          }
        }
      }
    }
    return out;
  }

  private static ensureFree(path: string): void {
    if (FileService.exists(path)) {
      throw new Error(Strings.get('err_already_exists', PathUtil.baseName(path)));
    }
  }
}
