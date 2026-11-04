import { ByteReader, ByteWriter, Utf8 } from './Bytes';
import { ByteStream } from './SshCrypto';
import { SshMsg } from './SshTransport';

/** Receive window we grant the server, and the largest packet we accept. */
export const CHANNEL_WINDOW: number = 2 * 1024 * 1024;
export const CHANNEL_MAX_PACKET: number = 32 * 1024;
/** Terminal mode opcode for IUTF8 (RFC 8160). */
const TTY_OP_IUTF8: number = 42;
const TTY_OP_END: number = 0;

/** What a channel needs from its connection. */
export interface ChannelOwner {
  sendPacket(payload: Uint8Array): void;
  releaseChannel(localId: number): void;
}

export type DataListener = (data: Uint8Array) => void;

/**
 * One SSH channel (RFC 4254): a session (shell, exec, subsystem) or a TCP tunnel. Handles flow
 * control in both directions; data that arrives before a listener is set is kept for it.
 */
export class SshChannel {
  readonly localId: number;
  remoteId: number = 0;
  /** Exit status from the server, -1 until known (or when the process died by a signal). */
  exitStatus: number = -1;
  exitSignal: string = '';
  private owner: ChannelOwner;
  private remoteWindow: number = 0;
  private remoteMaxPacket: number = 0;
  private localWindow: number = CHANNEL_WINDOW;
  private outQueue: Uint8Array[] = [];
  private replies: ((ok: boolean) => void)[] = [];
  private onData: DataListener | null = null;
  private onStderr: DataListener | null = null;
  private earlyData: Uint8Array[] = [];
  private earlyStderr: Uint8Array[] = [];
  private closeListeners: (() => void)[] = [];
  private eofListeners: (() => void)[] = [];
  private sentEof: boolean = false;
  private sentClose: boolean = false;
  private gotClose: boolean = false;
  private released: boolean = false;
  private wantEof: boolean = false;

  constructor(owner: ChannelOwner, localId: number) {
    this.owner = owner;
    this.localId = localId;
  }

  get isClosed(): boolean {
    return this.gotClose || this.sentClose;
  }

  // ---------- events ----------

  setOnData(l: DataListener): void {
    this.onData = l;
    const early = this.earlyData;
    this.earlyData = [];
    for (const d of early) {
      l(d);
    }
  }

  setOnStderr(l: DataListener): void {
    this.onStderr = l;
    const early = this.earlyStderr;
    this.earlyStderr = [];
    for (const d of early) {
      l(d);
    }
  }

  /** Called once the channel is fully closed (exit status, if any, is known by then). */
  onClose(l: () => void): void {
    if (this.released) {
      l();
      return;
    }
    this.closeListeners.push(l);
  }

  onEof(l: () => void): void {
    this.eofListeners.push(l);
  }

  // ---------- sending ----------

  write(data: Uint8Array): void {
    if (this.sentEof || this.isClosed) {
      return;
    }
    this.outQueue.push(data);
    this.flush();
  }

  writeText(text: string): void {
    this.write(Utf8.encode(text));
  }

  /** Tells the server no more data follows (sent after queued data). */
  eof(): void {
    this.wantEof = true;
    this.flush();
  }

  close(): void {
    if (this.sentClose || this.released) {
      return;
    }
    this.sentClose = true;
    this.owner.sendPacket(new ByteWriter().byte(SshMsg.CHANNEL_CLOSE).u32(this.remoteId).toBytes());
    if (this.gotClose) {
      this.release();
    }
  }

  /** A channel request; resolves with the server's answer (true right away when no reply is wanted). */
  request(type: string, data: Uint8Array, wantReply: boolean): Promise<boolean> {
    if (this.isClosed) {
      return Promise.resolve(false);
    }
    const p = new ByteWriter().byte(SshMsg.CHANNEL_REQUEST).u32(this.remoteId).str(type).bool(wantReply)
      .raw(data).toBytes();
    if (!wantReply) {
      this.owner.sendPacket(p);
      return Promise.resolve(true);
    }
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      this.replies.push(resolve);
      this.owner.sendPacket(p);
    });
  }

  requestPty(term: string, cols: number, rows: number): Promise<boolean> {
    const modes = new ByteWriter().byte(TTY_OP_IUTF8).u32(1).byte(TTY_OP_END).toBytes();
    return this.request('pty-req', new ByteWriter().str(term).u32(cols).u32(rows).u32(0).u32(0).bytes(modes).toBytes(),
      true);
  }

  shell(): Promise<boolean> {
    return this.request('shell', new Uint8Array(0), true);
  }

  exec(command: string): Promise<boolean> {
    return this.request('exec', new ByteWriter().str(command).toBytes(), true);
  }

  subsystem(name: string): Promise<boolean> {
    return this.request('subsystem', new ByteWriter().str(name).toBytes(), true);
  }

  setEnv(name: string, value: string): void {
    this.request('env', new ByteWriter().str(name).str(value).toBytes(), false);
  }

  resize(cols: number, rows: number): void {
    this.request('window-change', new ByteWriter().u32(cols).u32(rows).u32(0).u32(0).toBytes(), false);
  }

  /** Sends a signal such as 'INT', 'TERM' or 'KILL' (servers may ignore it). */
  signal(name: string): void {
    this.request('signal', new ByteWriter().str(name).toBytes(), false);
  }

  private flush(): void {
    while (this.outQueue.length > 0 && this.remoteWindow > 0 && !this.isClosed) {
      const head = this.outQueue[0];
      const n = Math.min(head.length, this.remoteWindow, this.remoteMaxPacket);
      if (n <= 0) {
        break;
      }
      const chunk = head.subarray(0, n);
      if (n === head.length) {
        this.outQueue.shift();
      } else {
        this.outQueue[0] = head.subarray(n);
      }
      this.remoteWindow -= n;
      this.owner.sendPacket(new ByteWriter().byte(SshMsg.CHANNEL_DATA).u32(this.remoteId).bytes(chunk).toBytes());
    }
    if (this.wantEof && this.outQueue.length === 0 && !this.sentEof && !this.isClosed) {
      this.sentEof = true;
      this.owner.sendPacket(new ByteWriter().byte(SshMsg.CHANNEL_EOF).u32(this.remoteId).toBytes());
    }
  }

  // ---------- from the connection ----------

  handleConfirm(remoteId: number, window: number, maxPacket: number): void {
    this.remoteId = remoteId;
    this.remoteWindow = window;
    this.remoteMaxPacket = Math.max(1, maxPacket);
    this.flush();
  }

  handleWindowAdjust(n: number): void {
    this.remoteWindow = Math.min(this.remoteWindow + n, 0xffffffff);
    this.flush();
  }

  handleData(data: Uint8Array, stderr: boolean): void {
    this.consume(data.length);
    const copy = data.slice();
    if (stderr) {
      if (this.onStderr !== null) {
        this.onStderr(copy);
      } else {
        this.earlyStderr.push(copy);
      }
    } else if (this.onData !== null) {
      this.onData(copy);
    } else {
      this.earlyData.push(copy);
    }
  }

  handleEof(): void {
    for (const l of this.eofListeners) {
      l();
    }
  }

  handleClose(): void {
    this.gotClose = true;
    if (!this.sentClose) {
      this.close();
    } else {
      this.release();
    }
  }

  handleRequest(type: string, wantReply: boolean, r: ByteReader): void {
    if (type === 'exit-status') {
      this.exitStatus = r.u32();
    } else if (type === 'exit-signal') {
      this.exitSignal = r.str();
    }
    if (wantReply && !this.isClosed) {
      this.owner.sendPacket(new ByteWriter().byte(SshMsg.CHANNEL_FAILURE).u32(this.remoteId).toBytes());
    }
  }

  handleReply(ok: boolean): void {
    const r = this.replies.shift();
    if (r !== undefined) {
      r(ok);
    }
  }

  /** The connection is gone: settle everything. */
  abort(): void {
    this.gotClose = true;
    this.sentClose = true;
    this.release();
  }

  private consume(n: number): void {
    this.localWindow -= n;
    if (this.localWindow < CHANNEL_WINDOW / 2 && !this.isClosed) {
      const add = CHANNEL_WINDOW - this.localWindow;
      this.localWindow = CHANNEL_WINDOW;
      this.owner.sendPacket(new ByteWriter().byte(SshMsg.CHANNEL_WINDOW_ADJUST).u32(this.remoteId).u32(add).toBytes());
    }
  }

  private release(): void {
    if (this.released) {
      return;
    }
    this.released = true;
    const pending = this.replies;
    this.replies = [];
    for (const r of pending) {
      r(false);
    }
    this.owner.releaseChannel(this.localId);
    const ls = this.closeListeners;
    this.closeListeners = [];
    for (const l of ls) {
      l();
    }
  }
}

/** A tunnel channel as a byte stream, so another SSH connection can run through a jump host. */
export class ChannelStream implements ByteStream {
  private ch: SshChannel;
  private closeListener: (error: string) => void = () => {
  };

  constructor(ch: SshChannel) {
    this.ch = ch;
    ch.onClose(() => this.closeListener(''));
  }

  write(data: Uint8Array): void {
    this.ch.write(data);
  }

  setOnData(listener: (data: Uint8Array) => void): void {
    this.ch.setOnData(listener);
  }

  setOnClose(listener: (error: string) => void): void {
    this.closeListener = listener;
  }

  close(): void {
    this.ch.close();
  }
}
