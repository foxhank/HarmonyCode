import { ByteReader, Bytes, ByteWriter, Utf8 } from '../remote/ssh/Bytes';
import { AeadCipher, ByteStream, Ed25519KeyPair, HashAlg, SshCrypto } from '../remote/ssh/SshCrypto';
import {
  AUTH_OK, LABEL, MAGIC, MAX_RECORD_BYTES, MODE_PAIR, MODE_RESUME, PROTOCOL_VERSION
} from './LinkProtocol';

/** A link failure with a message fit for the user. */
export class LinkError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LinkError';
  }
}

/** The same failure as a plain Error, for callbacks typed `(e: Error) => void`. */
export function linkFailure(message: string): Error {
  const e = new Error(message);
  e.name = 'LinkError';
  return e;
}

/** How to authenticate this connection. */
export interface LinkAuth {
  /** This phone's long-term identity. */
  identity: Ed25519KeyPair;
  /** Shown on the desktop's list of paired devices. */
  deviceName: string;
  /** The desktop's Ed25519 public key (from the QR code, or stored at pairing). */
  serverKey: Uint8Array;
  /** The one-time secret from the QR code when pairing; empty when resuming. */
  pairSecret: Uint8Array;
}

/** What the desktop said about itself. */
export interface DesktopInfo {
  name: string;
  workspace: string;
  os: string;
  hostname: string;
}

const HANDSHAKE_MAX: number = 4096;
const NONCE_LEN: number = 12;
const HANDSHAKE_TIMEOUT_MS: number = 15000;

class Direction {
  cipher: AeadCipher;
  counter: number = 0;

  constructor(cipher: AeadCipher) {
    this.cipher = cipher;
  }

  nonce(): Uint8Array {
    const n = new Uint8Array(NONCE_LEN);
    const hi = Math.floor(this.counter / 0x100000000);
    n.set(Bytes.u32(hi), 4);
    n.set(Bytes.u32(this.counter >>> 0), 8);
    this.counter++;
    return n;
  }
}

/**
 * The phone side of a HarmonyCode Link connection (docs/desktop-link.md sections 4-5): mutual
 * Ed25519 authentication over an X25519 key exchange, then AES-256-GCM records.
 */
export class LinkSession {
  info: DesktopInfo = { name: '', workspace: '', os: '', hostname: '' };
  private stream: ByteStream;
  private crypto: SshCrypto;
  private buf: Uint8Array = new Uint8Array(0);
  private send: Direction | null = null;
  private recv: Direction | null = null;
  private frameWaiter: ((frame: Uint8Array) => void) | null = null;
  private frames: Uint8Array[] = [];
  private onMessage: (plain: Uint8Array) => void = () => {
  };
  private closeListeners: ((error: string) => void)[] = [];
  private closed: boolean = false;
  private closeError: string = '';
  /** The handshake finished: frames are messages now. */
  private ready: boolean = false;
  private hasListener: boolean = false;

  private constructor(stream: ByteStream, crypto: SshCrypto) {
    this.stream = stream;
    this.crypto = crypto;
    stream.setOnData((d: Uint8Array) => this.onBytes(d));
    stream.setOnClose((e: string) => this.fail(e.length > 0 ? e : 'The desktop closed the connection.'));
  }

  /** Runs the handshake. Rejects with LinkError explaining what failed. */
  static async open(stream: ByteStream, crypto: SshCrypto, auth: LinkAuth): Promise<LinkSession> {
    const s = new LinkSession(stream, crypto);
    const timer = setTimeout(() => s.fail('The desktop did not answer the handshake.'), HANDSHAKE_TIMEOUT_MS);
    try {
      await s.handshake(auth);
    } catch (e) {
      s.close();
      throw e as Error;
    } finally {
      clearTimeout(timer);
    }
    return s;
  }

  get isClosed(): boolean {
    return this.closed;
  }

  setOnMessage(l: (plain: Uint8Array) => void): void {
    this.onMessage = l;
    this.hasListener = true;
    const pending = this.frames;
    this.frames = [];
    for (const f of pending) {
      this.deliver(f);
    }
  }

  onClose(l: (error: string) => void): void {
    if (this.closed) {
      l(this.closeError);
      return;
    }
    this.closeListeners.push(l);
  }

  /** Encrypts and sends one message. */
  write(plain: Uint8Array): void {
    const d = this.send;
    if (this.closed || d === null) {
      return;
    }
    if (plain.length > MAX_RECORD_BYTES) {
      throw new LinkError('Message too large.');
    }
    const len = Bytes.u32(plain.length + 16);
    this.stream.write(Bytes.concat([len, d.cipher.seal(d.nonce(), len, plain)]));
  }

  close(): void {
    if (!this.closed) {
      try {
        this.stream.close();
      } catch (e) {
        // already closed
      }
      this.fail('');
    }
  }

  // ---------- handshake ----------

  private async handshake(auth: LinkAuth): Promise<void> {
    const c = this.crypto;
    const eph = c.x25519Generate();
    const cr = c.random(16);
    const mode = auth.pairSecret.length > 0 ? MODE_PAIR : MODE_RESUME;
    const hello = new ByteWriter().raw(Utf8.encode(MAGIC)).byte(PROTOCOL_VERSION).byte(mode).raw(eph.publicKey).raw(cr)
      .toBytes();
    this.writeFrame(hello);
    const sh = await this.nextFrame();
    const r = new ByteReader(sh);
    if (Utf8.decode(r.raw(4)) !== MAGIC) {
      throw new LinkError('This is not a HarmonyCode desktop.');
    }
    if (r.byte() !== PROTOCOL_VERSION) {
      throw new LinkError('The desktop app uses a different protocol version. Update both apps.');
    }
    const se = r.raw(32).slice();
    r.raw(16);
    const spk = r.raw(32).slice();
    const sig = r.raw(64).slice();
    if (!Bytes.equal(spk, auth.serverKey)) {
      throw new LinkError('The desktop\'s identity does not match. If you reinstalled it, pair again.');
    }
    const h0 = c.hash(HashAlg.SHA256, Utf8.encode(LABEL));
    const h1 = c.hash(HashAlg.SHA256, Bytes.concat([h0, hello, sh.subarray(0, sh.length - 64)]));
    if (!c.ed25519Verify(spk, sig, h1)) {
      throw new LinkError('The desktop\'s signature is invalid.');
    }
    const ss = c.x25519Agree(eph.privateKey, se);
    const prk = c.hmac(HashAlg.SHA256, h1, ss);
    const kc2s = c.hmac(HashAlg.SHA256, prk, Bytes.concat([Utf8.encode('c2s'), new Uint8Array([1])]));
    const ks2c = c.hmac(HashAlg.SHA256, prk, Bytes.concat([Utf8.encode('s2c'), new Uint8Array([1])]));
    this.send = new Direction(c.aesGcm(kc2s));
    this.recv = new Direction(c.aesGcm(ks2c));
    const h2 = c.hash(HashAlg.SHA256, Bytes.concat([h1, Utf8.encode('client')]));
    const proof = mode === MODE_PAIR ? c.hmac(HashAlg.SHA256, auth.pairSecret, h2) : new Uint8Array(0);
    this.write(new ByteWriter().raw(auth.identity.publicKey).str(auth.deviceName)
      .raw(c.ed25519Sign(auth.identity, h2)).bytes(proof).toBytes());
    const reply = new ByteReader(await this.nextFrame());
    if (reply.byte() !== AUTH_OK) {
      throw new LinkError(reply.str());
    }
    this.info = { name: reply.str(), workspace: reply.str(), os: reply.str(), hostname: reply.str() };
    this.ready = true;
  }

  // ---------- frames ----------

  private writeFrame(payload: Uint8Array): void {
    this.stream.write(Bytes.concat([Bytes.u32(payload.length), payload]));
  }

  /** Next handshake frame (decrypted once keys exist). */
  private nextFrame(): Promise<Uint8Array> {
    const f = this.frames.shift();
    if (f !== undefined) {
      return Promise.resolve(f);
    }
    if (this.closed) {
      return Promise.reject(linkFailure(this.closeError.length > 0 ? this.closeError : 'Connection closed.'));
    }
    return new Promise<Uint8Array>((resolve: (f: Uint8Array) => void, reject: (e: Error) => void) => {
      this.frameWaiter = resolve;
      this.onClose((e: string) => reject(linkFailure(e.length > 0 ? e : 'Connection closed.')));
    });
  }

  private onBytes(data: Uint8Array): void {
    if (this.closed) {
      return;
    }
    this.buf = this.buf.length === 0 ? data.slice() : Bytes.concat([this.buf, data]);
    try {
      while (this.buf.length >= 4) {
        const len = Bytes.readU32(this.buf, 0);
        const max = this.recv === null ? HANDSHAKE_MAX : MAX_RECORD_BYTES + 16;
        if (len > max) {
          throw new LinkError('Oversized frame from the desktop.');
        }
        if (this.buf.length < 4 + len) {
          return;
        }
        let frame = this.buf.slice(4, 4 + len);
        const lenBytes = this.buf.slice(0, 4);
        this.buf = this.buf.slice(4 + len);
        const d = this.recv;
        if (d !== null) {
          try {
            frame = d.cipher.open(d.nonce(), lenBytes, frame);
          } catch (e) {
            throw new LinkError('A message failed authentication; the connection was closed.');
          }
        }
        this.deliver(frame);
      }
    } catch (e) {
      this.close();
      this.fail((e as Error).message);
    }
  }

  private deliver(frame: Uint8Array): void {
    if (this.frameWaiter !== null) {
      const w = this.frameWaiter;
      this.frameWaiter = null;
      w(frame);
    } else if (this.ready && this.hasListener) {
      this.onMessage(frame);
    } else {
      this.frames.push(frame);
    }
  }

  private fail(error: string): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    this.closeError = error;
    const ls = this.closeListeners;
    this.closeListeners = [];
    for (const l of ls) {
      l(error);
    }
  }
}
