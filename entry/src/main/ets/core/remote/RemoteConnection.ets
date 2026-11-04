import { ChannelStream } from './ssh/SshChannel';
import { SshClient } from './ssh/SshClient';
import { ByteStream, SocketFactory, SshCrypto } from './ssh/SshCrypto';
import { UserKey } from './ssh/SshKeys';
import { HostKeyInfo, SshError } from './ssh/SshTransport';
import { SftpClient } from './ssh/SftpClient';
import { AuthMethod, RemoteHost, RemoteOs, RemotePlatform } from './RemoteHost';
import { RemoteShell } from './RemoteShell';

/** Secrets for logging in, looked up when connecting. */
export interface RemoteSecrets {
  password(hostId: string): string;
  /** The app's own key, or null when none was created yet. */
  userKey(): UserKey | null;
}

/** Decides whether to trust a host key: silently when it matches the stored one, else by asking the user. */
export interface HostKeyTrust {
  check(host: RemoteHost, info: HostKeyInfo): Promise<boolean>;
}

/** Everything a connection needs from the platform and the app. */
export interface RemoteEnv {
  sockets: SocketFactory;
  crypto: SshCrypto;
  secrets: RemoteSecrets;
  trust: HostKeyTrust;
  /** Finds a saved host (for jump hosts). */
  lookup: (id: string) => RemoteHost | undefined;
  keepaliveMs: number;
  connectTimeoutMs: number;
}

export class ConnState {
  static readonly IDLE: string = 'idle';
  static readonly CONNECTING: string = 'connecting';
  static readonly CONNECTED: string = 'connected';
  static readonly FAILED: string = 'failed';
}

export type ConnListener = (state: string, error: string) => void;

/** Jump hosts chained deeper than this are refused (and loops caught). */
const MAX_JUMPS: number = 3;
const POSIX_PROBE: string = 'uname -s; uname -n; echo "$HOME"; echo "$SHELL"; if [ -r /etc/os-release ]; then ' +
  '. /etc/os-release; echo "$PRETTY_NAME"; elif command -v sw_vers >/dev/null 2>&1; then echo "macOS ' +
  '$(sw_vers -productVersion)"; else uname -sr; fi';
const WINDOWS_PROBE: string = '[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); ' +
  '$o = Get-CimInstance Win32_OperatingSystem; Write-Output $env:COMPUTERNAME; Write-Output $env:USERPROFILE; ' +
  'Write-Output ($o.Caption + \' \' + $o.Version)';

/**
 * The connection to one saved computer, shared by its terminal, file browser and agent. Connects
 * on demand (through a jump host when configured), learns the platform once, reconnects
 * transparently after the link drops, and keeps one SFTP session.
 */
export class RemoteConnection {
  readonly host: RemoteHost;
  state: string = ConnState.IDLE;
  error: string = '';
  platform: RemotePlatform | null = null;
  /** Pre-login banner from the server ('' if none). */
  banner: string = '';
  private env: RemoteEnv;
  private depth: number;
  private client: SshClient | null = null;
  private jump: RemoteConnection | null = null;
  private pending: Promise<SshClient> | null = null;
  private sftpClient: SftpClient | null = null;
  private sftpPending: Promise<SftpClient> | null = null;
  private listeners: ConnListener[] = [];
  private closedByUser: boolean = false;

  constructor(host: RemoteHost, env: RemoteEnv, depth: number = 0) {
    this.host = host;
    this.env = env;
    this.depth = depth;
  }

  get connected(): boolean {
    return this.client !== null && !this.client.isClosed;
  }

  onChange(l: ConnListener): () => void {
    this.listeners.push(l);
    return () => {
      this.listeners = this.listeners.filter((x: ConnListener) => x !== l);
    };
  }

  /** The live client, connecting (or reconnecting) first when needed. */
  connect(): Promise<SshClient> {
    if (this.client !== null && !this.client.isClosed) {
      return Promise.resolve(this.client);
    }
    if (this.pending !== null) {
      return this.pending;
    }
    this.closedByUser = false;
    this.setState(ConnState.CONNECTING, '');
    const p = this.open().then((c: SshClient) => {
      this.client = c;
      this.pending = null;
      c.onClose((err: string) => this.onLost(c, err));
      this.setState(ConnState.CONNECTED, '');
      return c;
    }).catch((e: Error) => {
      this.pending = null;
      this.setState(ConnState.FAILED, e.message);
      throw e;
    });
    this.pending = p;
    return p;
  }

  /** The SFTP session, opened on first use and reopened after reconnecting. */
  async sftp(): Promise<SftpClient> {
    const client = await this.connect();
    if (this.sftpClient !== null && !this.sftpClient.isClosed) {
      return this.sftpClient;
    }
    if (this.sftpPending === null) {
      this.sftpPending = SftpClient.open(client).then((s: SftpClient) => {
        this.sftpClient = s;
        this.sftpPending = null;
        return s;
      }).catch((e: Error) => {
        this.sftpPending = null;
        throw e;
      });
    }
    return this.sftpPending as Promise<SftpClient>;
  }

  /** Folder to start in, in SFTP form. */
  startDir(): string {
    const configured = this.host.startDir.trim();
    if (configured.length > 0) {
      return RemoteShell.toSftp(configured);
    }
    return this.platform !== null && this.platform.home.length > 0 ? this.platform.home : '/';
  }

  close(): void {
    this.closedByUser = true;
    if (this.client !== null) {
      this.client.close();
    }
    this.client = null;
    this.sftpClient = null;
    if (this.jump !== null) {
      this.jump.close();
      this.jump = null;
    }
    this.setState(ConnState.IDLE, '');
  }

  // ---------- internals ----------

  private async open(): Promise<SshClient> {
    const h = this.host;
    let stream: ByteStream;
    if (h.jumpHostId.length > 0) {
      const via = this.env.lookup(h.jumpHostId);
      if (via === undefined) {
        throw new SshError(`The jump host for "${h.name}" no longer exists. Edit the host.`);
      }
      if (this.depth >= MAX_JUMPS || via.id === h.id) {
        throw new SshError('Too many jump hosts (or a loop). Check the jump host settings.');
      }
      if (this.jump === null || this.jump.host.id !== via.id) {
        this.jump = new RemoteConnection(via, this.env, this.depth + 1);
      }
      const jc = await this.jump.connect();
      const ch = await jc.openDirectTcpip(h.host, h.port).catch((e: Error) => {
        throw new SshError(`${via.name} could not reach ${h.host}:${h.port}: ${e.message}`);
      });
      stream = new ChannelStream(ch);
    } else {
      stream = await this.env.sockets.connect(h.host, h.port, this.env.connectTimeoutMs);
    }
    const usePassword = h.auth === AuthMethod.PASSWORD;
    const key = usePassword ? null : this.env.secrets.userKey();
    if (!usePassword && key === null) {
      stream.close();
      throw new SshError('No HarmonyCode key exists yet. Create one in the host settings and add it to the server.');
    }
    this.banner = '';
    const client = await SshClient.connect(stream, this.env.crypto, {
      auth: { username: h.username, password: usePassword ? this.env.secrets.password(h.id) : '', key: key },
      verifyHostKey: (info: HostKeyInfo) => this.env.trust.check(h, info),
      keepaliveMs: this.env.keepaliveMs,
      onBanner: (text: string) => {
        this.banner += text;
      }
    });
    if (this.platform === null) {
      try {
        this.platform = await RemoteConnection.probe(client);
      } catch (e) {
        this.platform = { os: RemoteOs.UNKNOWN, release: '', home: '/', shell: '', hostname: h.host };
      }
    }
    return client;
  }

  /** Learns the OS, home folder and shell with one or two commands. */
  static async probe(c: SshClient): Promise<RemotePlatform> {
    const posix = await c.exec('sh -c ' + RemoteShell.sh(POSIX_PROBE));
    if (posix.exitCode === 0) {
      const l = posix.stdout.split('\n').map((s: string) => s.trim());
      const kernel = l[0] ?? '';
      const os = kernel === 'Linux' ? RemoteOs.LINUX : (kernel === 'Darwin' ? RemoteOs.MACOS : RemoteOs.UNIX);
      return { os: os, hostname: l[1] ?? '', home: l[2] ?? '/', shell: l[3] ?? '', release: l[4] ?? kernel };
    }
    const win = await c.exec(RemoteShell.powershell(WINDOWS_PROBE));
    if (win.exitCode === 0) {
      const l = win.stdout.split('\n').map((s: string) => s.trim());
      return {
        os: RemoteOs.WINDOWS, hostname: l[0] ?? '', home: RemoteShell.toSftp(l[1] ?? 'C:\\'), shell: 'powershell',
        release: l[2] ?? 'Windows'
      };
    }
    return { os: RemoteOs.UNKNOWN, release: '', home: '/', shell: '', hostname: '' };
  }

  private onLost(c: SshClient, err: string): void {
    if (this.client !== c) {
      return;
    }
    this.client = null;
    this.sftpClient = null;
    if (!this.closedByUser) {
      this.setState(ConnState.FAILED, err.length > 0 ? err : 'Connection closed.');
    }
  }

  private setState(state: string, error: string): void {
    this.state = state;
    this.error = error;
    for (const l of this.listeners.slice()) {
      l(state, error);
    }
  }
}
