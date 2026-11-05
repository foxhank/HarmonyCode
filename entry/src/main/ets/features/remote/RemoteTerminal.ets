import { Strings } from '../../core/common/Strings';
import { RemoteConnection } from '../../core/remote/RemoteConnection';
import { hostAddress, RemoteOs } from '../../core/remote/RemoteHost';
import { RemoteShell } from '../../core/remote/RemoteShell';
import { Utf8, Utf8Decoder } from '../../core/remote/ssh/Bytes';
import { SshChannel } from '../../core/remote/ssh/SshChannel';
import { SettingsStore } from '../../core/settings/SettingsStore';
import { OutputSink, ShellBackend } from '../../core/terminal/ShellBackend';
import { TerminalController, TerminalTheme } from '../terminal/TerminalController';

const TERM: string = 'xterm-256color';
const DIM: string = '\x1b[2m';
const RED: string = '\x1b[31m';
const RESET: string = '\x1b[0m';
const NL: string = '\r\n';

/** Folder a new shell should start in ('' = the host's start folder). */
export type StartDirProvider = () => Promise<string>;

/**
 * An interactive login shell on the remote computer, in a pseudo-terminal. When the connection
 * drops it says so and reconnects on Enter (phones lose connections when they sleep).
 */
export class SshShellBackend implements ShellBackend {
  private conn: RemoteConnection;
  private sink: OutputSink;
  private dirProvider: StartDirProvider | null;
  private ch: SshChannel | null = null;
  private opening: boolean = false;
  private cols: number = 80;
  private rows: number = 24;
  private stopped: boolean = false;

  constructor(conn: RemoteConnection, sink: OutputSink, dirProvider: StartDirProvider | null = null) {
    this.conn = conn;
    this.sink = sink;
    this.dirProvider = dirProvider;
  }

  label(): string {
    return hostAddress(this.conn.host);
  }

  start(cols: number, rows: number): void {
    this.cols = cols;
    this.rows = rows;
    this.open();
  }

  input(data: string): void {
    if (this.ch !== null && !this.ch.isClosed) {
      this.ch.write(Utf8.encode(data));
    } else if (!this.opening && data.indexOf('\r') >= 0) {
      this.open();
    }
  }

  resize(cols: number, rows: number): void {
    this.cols = cols;
    this.rows = rows;
    if (this.ch !== null && !this.ch.isClosed) {
      this.ch.resize(cols, rows);
    }
  }

  runLine(line: string): void {
    this.input(line + '\r');
  }

  stop(): void {
    this.stopped = true;
    if (this.ch !== null) {
      this.ch.close();
      this.ch = null;
    }
  }

  private async open(): Promise<void> {
    if (this.opening || this.stopped) {
      return;
    }
    this.opening = true;
    this.sink(DIM + Strings.get('remote_term_connecting', hostAddress(this.conn.host)) + RESET + NL);
    try {
      const client = await this.conn.connect();
      if (this.conn.banner.trim().length > 0) {
        this.sink(this.conn.banner.replace(new RegExp('\\r?\\n', 'g'), NL));
      }
      const ch = await client.openSession();
      const decoder = new Utf8Decoder();
      ch.setOnData((d: Uint8Array) => this.sink(decoder.write(d)));
      ch.setOnStderr((d: Uint8Array) => this.sink(decoder.write(d)));
      ch.onClose(() => this.onClosed(ch));
      if (!await ch.requestPty(TERM, this.cols, this.rows) || !await ch.shell()) {
        ch.close();
        throw new Error(Strings.get('remote_term_refused'));
      }
      this.ch = ch;
      this.enterStartDir(ch, this.dirProvider !== null ? await this.dirProvider() : '');
    } catch (e) {
      this.sink(RED + (e as Error).message + RESET + NL + DIM + Strings.get('remote_term_retry') + RESET + NL);
    } finally {
      this.opening = false;
    }
  }

  /** Moves the new shell into `preferred`, else the host's configured start folder, if any. */
  private enterStartDir(ch: SshChannel, preferred: string): void {
    const dir = preferred.length > 0 ? preferred : this.conn.host.startDir.trim();
    if (dir.length === 0) {
      return;
    }
    const windows = this.conn.platform !== null && this.conn.platform.os === RemoteOs.WINDOWS;
    const native = windows ? RemoteShell.toWindows(RemoteShell.toSftp(dir)) : dir;
    // `cd "path"` works in bash, zsh, fish, cmd and PowerShell alike.
    ch.write(Utf8.encode('cd "' + native.split('"').join('') + '"\r'));
  }

  private onClosed(ch: SshChannel): void {
    if (this.ch !== ch) {
      return;
    }
    this.ch = null;
    if (this.stopped) {
      return;
    }
    const why = this.conn.connected ? Strings.get('remote_term_ended') :
      (this.conn.error.length > 0 ? this.conn.error : Strings.get('remote_term_lost'));
    this.sink(NL + DIM + why + ' ' + Strings.get('remote_term_retry') + RESET + NL);
  }
}

/** The terminal of a remote workspace. */
@ObservedV2
export class RemoteTerminalModel extends TerminalController {
  constructor(conn: RemoteConnection, settings: SettingsStore, themeFn: () => TerminalTheme) {
    super(settings, themeFn);
    this.session.setBackend(new SshShellBackend(conn, this.session.output));
    this.label = this.session.label();
  }
}
