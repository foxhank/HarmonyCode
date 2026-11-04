import { ByteReader, ByteWriter, Utf8Decoder } from './Bytes';
import { CHANNEL_MAX_PACKET, CHANNEL_WINDOW, ChannelOwner, SshChannel } from './SshChannel';
import { ByteStream, SshCrypto } from './SshCrypto';
import { SshKeys, UserKey } from './SshKeys';
import { HostKeyVerifier, SshError, sshFailure, SshMsg, SshTransport } from './SshTransport';

/** How to log in. Methods are tried in the order: public key, keyboard-interactive, password. */
export interface SshAuth {
  username: string;
  /** '' = no password. Used for both "password" and "keyboard-interactive". */
  password: string;
  key: UserKey | null;
}

export interface SshClientOptions {
  auth: SshAuth;
  verifyHostKey: HostKeyVerifier;
  /** Keepalive interval; 0 disables keepalives. */
  keepaliveMs: number;
  /** Pre-login banner text from the server. */
  onBanner: (text: string) => void;
}

/** Output and status of a command run with exec(). */
export interface ExecResult {
  exitCode: number;
  signal: string;
  stdout: string;
  stderr: string;
}

const SERVICE_AUTH: string = 'ssh-userauth';
const SERVICE_CONNECTION: string = 'ssh-connection';
const METHOD_PUBLICKEY: string = 'publickey';
const METHOD_KBD: string = 'keyboard-interactive';
const METHOD_PASSWORD: string = 'password';
const ED25519: string = 'ssh-ed25519';
/** Missed keepalive replies before the connection is considered dead. */
const KEEPALIVE_MAX_MISSED: number = 3;
/** Keyboard-interactive rounds answered with the password before giving up. */
const KBD_MAX_ROUNDS: number = 3;

class PendingOpen {
  channel: SshChannel;
  resolve: (c: SshChannel) => void;
  reject: (e: Error) => void;

  constructor(channel: SshChannel, resolve: (c: SshChannel) => void, reject: (e: Error) => void) {
    this.channel = channel;
    this.resolve = resolve;
    this.reject = reject;
  }
}

/**
 * An authenticated SSH connection (RFC 4252 / 4254): logs in, then multiplexes channels for
 * shells, commands, SFTP and TCP tunnels. Keeps the connection alive and notices when it dies.
 */
export class SshClient implements ChannelOwner {
  readonly transport: SshTransport;
  private channels: Map<number, SshChannel> = new Map();
  private opens: Map<number, PendingOpen> = new Map();
  private nextId: number = 0;
  private authQueue: Uint8Array[] = [];
  private authWaiter: ((p: Uint8Array) => void) | null = null;
  private authenticated: boolean = false;
  private keepaliveTimer: number = -1;
  private missed: number = 0;
  private closeListeners: ((error: string) => void)[] = [];
  private closeError: string = '';
  private closed: boolean = false;

  private constructor(transport: SshTransport) {
    this.transport = transport;
    transport.setHandler((p: Uint8Array) => this.onPacket(p));
    transport.onClose((e: string) => this.onTransportClosed(e));
  }

  /** Runs the handshake and logs in. Rejects with SshError explaining what failed. */
  static async connect(stream: ByteStream, crypto: SshCrypto, options: SshClientOptions): Promise<SshClient> {
    const transport = new SshTransport(stream, crypto, options.verifyHostKey);
    const client = new SshClient(transport);
    try {
      await transport.start();
      await client.authenticate(options);
    } catch (e) {
      client.close();
      throw e as Error;
    }
    client.startKeepalive(options.keepaliveMs);
    return client;
  }

  get isClosed(): boolean {
    return this.closed;
  }

  /** Why the connection closed ('' while open or after a normal close). */
  get lastError(): string {
    return this.closeError;
  }

  onClose(l: (error: string) => void): void {
    if (this.closed) {
      l(this.closeError);
      return;
    }
    this.closeListeners.push(l);
  }

  close(): void {
    this.transport.disconnect('Bye');
  }

  openSession(): Promise<SshChannel> {
    return this.open('session', new Uint8Array(0));
  }

  /** A TCP connection from the server to host:port (for jump hosts and port forwarding). */
  openDirectTcpip(host: string, port: number): Promise<SshChannel> {
    return this.open('direct-tcpip', new ByteWriter().str(host).u32(port).str('127.0.0.1').u32(0).toBytes());
  }

  /** Runs a command without a terminal and collects its output. */
  async exec(command: string): Promise<ExecResult> {
    const ch = await this.openSession();
    const out = new Utf8Decoder();
    const err = new Utf8Decoder();
    let stdout = '';
    let stderr = '';
    ch.setOnData((d: Uint8Array) => {
      stdout += out.write(d);
    });
    ch.setOnStderr((d: Uint8Array) => {
      stderr += err.write(d);
    });
    return new Promise<ExecResult>((resolve: (r: ExecResult) => void, reject: (e: Error) => void) => {
      ch.onClose(() => {
        resolve({ exitCode: ch.exitStatus, signal: ch.exitSignal, stdout: stdout + out.end(), stderr: stderr + err.end() });
      });
      ch.exec(command).then((ok: boolean) => {
        if (!ok) {
          ch.close();
          reject(sshFailure('The server refused to run the command.'));
        } else {
          ch.eof();
        }
      });
    });
  }

  // ---------- ChannelOwner ----------

  sendPacket(payload: Uint8Array): void {
    this.transport.send(payload);
  }

  releaseChannel(localId: number): void {
    this.channels.delete(localId);
  }

  // ---------- authentication ----------

  private nextAuthPacket(): Promise<Uint8Array> {
    const p = this.authQueue.shift();
    if (p !== undefined) {
      return Promise.resolve(p);
    }
    if (this.closed) {
      return Promise.reject(new SshError(this.closeError.length > 0 ? this.closeError : 'Connection closed.'));
    }
    return new Promise<Uint8Array>((resolve: (p: Uint8Array) => void) => {
      this.authWaiter = resolve;
    });
  }

  /** Next auth reply, delivering banners on the way. */
  private async authReply(options: SshClientOptions): Promise<Uint8Array> {
    while (true) {
      const p = await this.nextAuthPacket();
      if (p.length === 0) {
        throw new SshError(this.closeError.length > 0 ? this.closeError : 'Connection closed during login.');
      }
      if (p[0] === SshMsg.USERAUTH_BANNER) {
        options.onBanner(new ByteReader(p, 1).str());
        continue;
      }
      return p;
    }
  }

  private async authenticate(options: SshClientOptions): Promise<void> {
    const auth = options.auth;
    this.transport.send(new ByteWriter().byte(SshMsg.SERVICE_REQUEST).str(SERVICE_AUTH).toBytes());
    const accept = await this.authReply(options);
    if (accept[0] !== SshMsg.SERVICE_ACCEPT) {
      throw new SshError('The server refused the authentication service.');
    }
    this.transport.send(this.authHeader(auth.username, 'none').toBytes());
    let reply = await this.authReply(options);
    const tried: Set<string> = new Set();
    let lastMethods: string[] = [];
    while (reply[0] !== SshMsg.USERAUTH_SUCCESS) {
      if (reply[0] !== SshMsg.USERAUTH_FAILURE) {
        throw new SshError('Unexpected reply during login (' + reply[0] + ').');
      }
      lastMethods = new ByteReader(reply, 1).nameList();
      if (auth.key !== null && lastMethods.indexOf(METHOD_PUBLICKEY) >= 0 && !tried.has(METHOD_PUBLICKEY)) {
        tried.add(METHOD_PUBLICKEY);
        this.sendPublicKey(auth.username, auth.key);
        reply = await this.authReply(options);
      } else if (auth.password.length > 0 && lastMethods.indexOf(METHOD_KBD) >= 0 && !tried.has(METHOD_KBD)) {
        tried.add(METHOD_KBD);
        reply = await this.keyboardInteractive(auth, options);
      } else if (auth.password.length > 0 && lastMethods.indexOf(METHOD_PASSWORD) >= 0 && !tried.has(METHOD_PASSWORD)) {
        tried.add(METHOD_PASSWORD);
        this.transport.send(this.authHeader(auth.username, METHOD_PASSWORD).bool(false).str(auth.password).toBytes());
        reply = await this.authReply(options);
        if (reply[0] === SshMsg.USERAUTH_INFO_REQUEST) {
          throw new SshError('The server says the password has expired. Change it in a regular SSH session first.');
        }
      } else {
        throw new SshError(SshClient.authFailure(auth, tried, lastMethods));
      }
    }
    this.authenticated = true;
    this.authQueue = [];
  }

  private static authFailure(auth: SshAuth, tried: Set<string>, methods: string[]): string {
    if (tried.size === 0) {
      if (methods.indexOf(METHOD_PUBLICKEY) >= 0 && methods.indexOf(METHOD_PASSWORD) < 0 &&
        methods.indexOf(METHOD_KBD) < 0) {
        return 'The server only accepts key login. Add HarmonyCode\'s public key to ~/.ssh/authorized_keys on the server.';
      }
      return 'No usable login method. The server accepts: ' + methods.join(', ') + '.';
    }
    const usedKey = tried.has(METHOD_PUBLICKEY);
    const usedPassword = tried.has(METHOD_PASSWORD) || tried.has(METHOD_KBD);
    if (usedKey && !usedPassword) {
      return 'The server rejected the key for "' + auth.username + '". Check that the public key is in ' +
        '~/.ssh/authorized_keys (on Windows administrators: C:\\ProgramData\\ssh\\administrators_authorized_keys).';
    }
    return 'Login failed for "' + auth.username + '": wrong user name, password or key.';
  }

  private authHeader(user: string, method: string): ByteWriter {
    return new ByteWriter().byte(SshMsg.USERAUTH_REQUEST).str(user).str(SERVICE_CONNECTION).str(method);
  }

  private sendPublicKey(user: string, key: UserKey): void {
    const blob = SshKeys.ed25519Blob(key.pair.publicKey);
    const signed = new ByteWriter()
      .bytes(this.transport.sessionId)
      .byte(SshMsg.USERAUTH_REQUEST).str(user).str(SERVICE_CONNECTION).str(METHOD_PUBLICKEY)
      .bool(true).str(ED25519).bytes(blob)
      .toBytes();
    const sig = SshKeys.ed25519Signature(this.transport.crypto, key.pair, signed);
    this.transport.send(this.authHeader(user, METHOD_PUBLICKEY).bool(true).str(ED25519).bytes(blob).bytes(sig).toBytes());
  }

  private async keyboardInteractive(auth: SshAuth, options: SshClientOptions): Promise<Uint8Array> {
    this.transport.send(this.authHeader(auth.username, METHOD_KBD).str('').str('').toBytes());
    let rounds = 0;
    while (true) {
      const p = await this.authReply(options);
      if (p[0] !== SshMsg.USERAUTH_INFO_REQUEST) {
        return p;
      }
      const r = new ByteReader(p, 1);
      r.str(); // name
      const instruction = r.str();
      r.str(); // language
      const n = r.u32();
      if (instruction.trim().length > 0) {
        options.onBanner(instruction);
      }
      if (n > 0) {
        rounds++;
        if (rounds > KBD_MAX_ROUNDS) {
          throw new SshError('Login failed for "' + auth.username + '": wrong password.');
        }
      }
      const w = new ByteWriter().byte(SshMsg.USERAUTH_INFO_RESPONSE).u32(n);
      for (let i = 0; i < n; i++) {
        r.str();
        r.bool();
        w.str(auth.password);
      }
      this.transport.send(w.toBytes());
    }
  }

  // ---------- connection protocol ----------

  private open(type: string, extra: Uint8Array): Promise<SshChannel> {
    if (this.closed) {
      return Promise.reject(new SshError(this.closeError.length > 0 ? this.closeError : 'Not connected.'));
    }
    const id = this.nextId++;
    const ch = new SshChannel(this, id);
    return new Promise<SshChannel>((resolve: (c: SshChannel) => void, reject: (e: Error) => void) => {
      this.opens.set(id, new PendingOpen(ch, resolve, reject));
      this.transport.send(new ByteWriter().byte(SshMsg.CHANNEL_OPEN).str(type).u32(id).u32(CHANNEL_WINDOW)
        .u32(CHANNEL_MAX_PACKET).raw(extra).toBytes());
    });
  }

  private onPacket(p: Uint8Array): void {
    if (!this.authenticated) {
      if (this.authWaiter !== null) {
        const w = this.authWaiter;
        this.authWaiter = null;
        w(p);
      } else {
        this.authQueue.push(p);
      }
      return;
    }
    const type = p[0];
    const r = new ByteReader(p, 1);
    if (type === SshMsg.REQUEST_SUCCESS || type === SshMsg.REQUEST_FAILURE) {
      this.missed = 0;
      return;
    }
    if (type === SshMsg.GLOBAL_REQUEST) {
      r.str();
      if (r.bool()) {
        this.transport.send(new Uint8Array([SshMsg.REQUEST_FAILURE]));
      }
      return;
    }
    if (type === SshMsg.CHANNEL_OPEN) {
      r.str();
      const sender = r.u32();
      // 1 = SSH_OPEN_ADMINISTRATIVELY_PROHIBITED: we never accept channels from the server.
      this.transport.send(new ByteWriter().byte(SshMsg.CHANNEL_OPEN_FAILURE).u32(sender).u32(1)
        .str('not supported').str('').toBytes());
      return;
    }
    if (type < SshMsg.CHANNEL_OPEN_CONFIRMATION || type > SshMsg.CHANNEL_FAILURE) {
      return;
    }
    const local = r.u32();
    if (type === SshMsg.CHANNEL_OPEN_CONFIRMATION || type === SshMsg.CHANNEL_OPEN_FAILURE) {
      const pending = this.opens.get(local);
      if (pending === undefined) {
        return;
      }
      this.opens.delete(local);
      if (type === SshMsg.CHANNEL_OPEN_CONFIRMATION) {
        const remote = r.u32();
        const window = r.u32();
        const maxPacket = r.u32();
        this.channels.set(local, pending.channel);
        pending.channel.handleConfirm(remote, window, maxPacket);
        pending.resolve(pending.channel);
      } else {
        r.u32();
        const why = r.str();
        pending.reject(sshFailure('The server refused to open a channel' + (why.length > 0 ? ': ' + why : '.')));
      }
      return;
    }
    // Most messages count as signs of life too.
    this.missed = 0;
    const ch = this.channels.get(local);
    if (ch === undefined) {
      return;
    }
    switch (type) {
      case SshMsg.CHANNEL_WINDOW_ADJUST:
        ch.handleWindowAdjust(r.u32());
        break;
      case SshMsg.CHANNEL_DATA:
        ch.handleData(r.bytes(), false);
        break;
      case SshMsg.CHANNEL_EXTENDED_DATA:
        r.u32();
        ch.handleData(r.bytes(), true);
        break;
      case SshMsg.CHANNEL_EOF:
        ch.handleEof();
        break;
      case SshMsg.CHANNEL_CLOSE:
        ch.handleClose();
        break;
      case SshMsg.CHANNEL_REQUEST: {
        const name = r.str();
        const want = r.bool();
        ch.handleRequest(name, want, r);
        break;
      }
      case SshMsg.CHANNEL_SUCCESS:
        ch.handleReply(true);
        break;
      case SshMsg.CHANNEL_FAILURE:
        ch.handleReply(false);
        break;
      default:
        break;
    }
  }

  private startKeepalive(ms: number): void {
    if (ms <= 0) {
      return;
    }
    this.keepaliveTimer = setInterval(() => {
      if (this.closed) {
        return;
      }
      this.missed++;
      if (this.missed > KEEPALIVE_MAX_MISSED) {
        this.transport.disconnect('Keepalive timeout', 'Connection lost (the server stopped responding).');
        return;
      }
      this.transport.send(new ByteWriter().byte(SshMsg.GLOBAL_REQUEST).str('keepalive@openssh.com').bool(true).toBytes());
    }, ms);
  }

  private onTransportClosed(error: string): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    if (this.closeError.length === 0) {
      this.closeError = error;
    }
    if (this.keepaliveTimer >= 0) {
      clearInterval(this.keepaliveTimer);
      this.keepaliveTimer = -1;
    }
    // Wake a pending login step: an empty packet means "closed".
    if (this.authWaiter !== null) {
      const w = this.authWaiter;
      this.authWaiter = null;
      w(new Uint8Array(0));
    }
    for (const o of this.opens.values()) {
      o.reject(sshFailure(this.closeError.length > 0 ? this.closeError : 'Connection closed.'));
    }
    this.opens.clear();
    for (const ch of Array.from(this.channels.values())) {
      ch.abort();
    }
    this.channels.clear();
    const ls = this.closeListeners;
    this.closeListeners = [];
    for (const l of ls) {
      l(this.closeError);
    }
  }
}
