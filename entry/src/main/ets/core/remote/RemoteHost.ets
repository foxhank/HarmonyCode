/** How a saved computer is logged into. */
export class AuthMethod {
  /** HarmonyCode's own Ed25519 key (its public key goes into the server's authorized_keys). */
  static readonly KEY: string = 'key';
  static readonly PASSWORD: string = 'password';
}

/** A computer the user connects to over SSH. Secrets live elsewhere (the system Asset Store). */
export interface RemoteHost {
  id: string;
  /** Display name, e.g. "Home PC". */
  name: string;
  host: string;
  port: number;
  username: string;
  auth: string;
  /** Another saved host to tunnel through ('' = connect directly). */
  jumpHostId: string;
  /** Folder the agent and terminal start in ('' = the user's home). */
  startDir: string;
  lastUsed: number;
}

export const SSH_DEFAULT_PORT: number = 22;

export function hostAddress(h: RemoteHost): string {
  return h.username + '@' + h.host + (h.port !== SSH_DEFAULT_PORT ? ':' + h.port : '');
}

/** Operating systems the remote layer adapts to. */
export class RemoteOs {
  static readonly LINUX: string = 'linux';
  static readonly MACOS: string = 'macos';
  static readonly WINDOWS: string = 'windows';
  /** Another POSIX system (BSD, ...). */
  static readonly UNIX: string = 'unix';
  static readonly UNKNOWN: string = '';
}

/** What was learned about the computer after connecting. */
export interface RemotePlatform {
  os: string;
  /** e.g. "Ubuntu 24.04.1 LTS", "Windows 11 Pro 10.0.26100", "macOS 15.1". */
  release: string;
  /** Home folder in SFTP form ("/home/dev", "/C:/Users/dev"). */
  home: string;
  /** Login shell on POSIX systems, e.g. "/bin/bash". */
  shell: string;
  hostname: string;
}
