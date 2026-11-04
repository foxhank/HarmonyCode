import { Base64 } from './ssh/Bytes';

const DRIVE_SFTP: RegExp = new RegExp('^/([A-Za-z]):(/|$)');
const DRIVE_NATIVE: RegExp = new RegExp('^([A-Za-z]):([\\\\/]|$)');

/** Paths and quoting for the shells on the other end. */
export class RemoteShell {
  /** POSIX single-quoted string. */
  static sh(s: string): string {
    return '\'' + s.split('\'').join('\'\\\'\'') + '\'';
  }

  /** PowerShell single-quoted string. */
  static ps(s: string): string {
    return '\'' + s.split('\'').join('\'\'') + '\'';
  }

  /** `powershell.exe ... -EncodedCommand`: immune to whatever the default SSH shell (cmd or PowerShell) is. */
  static powershell(script: string): string {
    const bytes = new Uint8Array(script.length * 2);
    for (let i = 0; i < script.length; i++) {
      const c = script.charCodeAt(i);
      bytes[i * 2] = c & 0xff;
      bytes[i * 2 + 1] = c >> 8;
    }
    return 'powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' +
      Base64.encode(bytes);
  }

  /** "C:\Users\dev" or "C:/Users/dev" -> "/C:/Users/dev" (how Windows OpenSSH's SFTP names paths). */
  static toSftp(path: string): string {
    const p = path.trim().replace(new RegExp('\\\\', 'g'), '/');
    return DRIVE_NATIVE.test(p) ? '/' + p : p;
  }

  /** "/C:/Users/dev" -> "C:\Users\dev" for Windows commands; POSIX paths unchanged. */
  static toWindows(path: string): string {
    const m = DRIVE_SFTP.exec(path);
    if (m === null) {
      return path;
    }
    const rest = path.substring(3).replace(new RegExp('/', 'g'), '\\');
    return m[1].toUpperCase() + ':' + (rest.length > 0 ? rest : '\\');
  }
}
