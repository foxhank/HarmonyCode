import { ByteReader, Bytes, ByteWriter, Utf8 } from './Bytes';
import { AeadCipher, ByteStream, HashAlg, SshCrypto, StreamCipher } from './SshCrypto';
import { HOST_KEY_ALGORITHMS, SshKeys } from './SshKeys';

/** SSH message numbers (RFC 4250). */
export class SshMsg {
  static readonly DISCONNECT: number = 1;
  static readonly IGNORE: number = 2;
  static readonly UNIMPLEMENTED: number = 3;
  static readonly DEBUG: number = 4;
  static readonly SERVICE_REQUEST: number = 5;
  static readonly SERVICE_ACCEPT: number = 6;
  static readonly EXT_INFO: number = 7;
  static readonly KEXINIT: number = 20;
  static readonly NEWKEYS: number = 21;
  static readonly KEX_INIT: number = 30;
  static readonly KEX_REPLY: number = 31;
  static readonly USERAUTH_REQUEST: number = 50;
  static readonly USERAUTH_FAILURE: number = 51;
  static readonly USERAUTH_SUCCESS: number = 52;
  static readonly USERAUTH_BANNER: number = 53;
  static readonly USERAUTH_INFO_REQUEST: number = 60;
  static readonly USERAUTH_INFO_RESPONSE: number = 61;
  static readonly GLOBAL_REQUEST: number = 80;
  static readonly REQUEST_SUCCESS: number = 81;
  static readonly REQUEST_FAILURE: number = 82;
  static readonly CHANNEL_OPEN: number = 90;
  static readonly CHANNEL_OPEN_CONFIRMATION: number = 91;
  static readonly CHANNEL_OPEN_FAILURE: number = 92;
  static readonly CHANNEL_WINDOW_ADJUST: number = 93;
  static readonly CHANNEL_DATA: number = 94;
  static readonly CHANNEL_EXTENDED_DATA: number = 95;
  static readonly CHANNEL_EOF: number = 96;
  static readonly CHANNEL_CLOSE: number = 97;
  static readonly CHANNEL_REQUEST: number = 98;
  static readonly CHANNEL_SUCCESS: number = 99;
  static readonly CHANNEL_FAILURE: number = 100;
}

/** An SSH failure with a message fit for the user. */
export class SshError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SshError';
  }
}

/**
 * The same failure as a plain Error, for callbacks typed `(e: Error) => void` (ArkTS does not let
 * subclasses be passed there).
 */
export function sshFailure(message: string): Error {
  const e = new Error(message);
  e.name = 'SshError';
  return e;
}

/** The server's host key, for the user to trust (first connection) or for checking against the stored one. */
export interface HostKeyInfo {
  algorithm: string;
  blob: Uint8Array;
  fingerprint: string;
}

/** Resolves true to trust the key and continue. */
export type HostKeyVerifier = (info: HostKeyInfo) => Promise<boolean>;

const CLIENT_VERSION: string = 'SSH-2.0-HarmonyCode_1.0';
const KEX_CURVE25519: string = 'curve25519-sha256';
const KEX_CURVE25519_LIBSSH: string = 'curve25519-sha256@libssh.org';
const KEX_DH14: string = 'diffie-hellman-group14-sha256';
const EXT_INFO_C: string = 'ext-info-c';
const STRICT_C: string = 'kex-strict-c-v00@openssh.com';
const STRICT_S: string = 'kex-strict-s-v00@openssh.com';
const CIPHERS: string[] = ['aes256-gcm@openssh.com', 'aes128-gcm@openssh.com', 'aes256-ctr', 'aes128-ctr'];
const MACS: string[] = ['hmac-sha2-256-etm@openssh.com', 'hmac-sha2-512-etm@openssh.com', 'hmac-sha2-256',
  'hmac-sha2-512'];
const MAX_PACKET: number = 1024 * 1024;
const MAX_VERSION_BYTES: number = 16 * 1024;
const GCM_TAG: number = 16;
const GCM_IV: number = 12;
const AES_BLOCK: number = 16;
const PLAIN_BLOCK: number = 8;
const MIN_PADDING: number = 4;
/** Re-key after this much traffic in either direction. */
const REKEY_BYTES: number = 1024 * 1024 * 1024;
const DH_EXPONENT_BYTES: number = 64;
const DH14_PRIME: string =
  'FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DD' +
  'EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED' +
  'EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F' +
  '83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B' +
  'E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA0510' +
  '15728E5A8AACAA68FFFFFFFFFFFFFFFF';

/** Encryption state of one direction. */
class CipherState {
  mode: string = 'none';
  gcm: AeadCipher | null = null;
  nonce: Uint8Array = new Uint8Array(GCM_IV);
  ctr: StreamCipher | null = null;
  macAlg: string = '';
  macKey: Uint8Array = new Uint8Array(0);
  macLen: number = 0;
  etm: boolean = false;

  get blockSize(): number {
    return this.mode === 'none' ? PLAIN_BLOCK : AES_BLOCK;
  }

  /** GCM: the last 8 bytes of the nonce are a big-endian packet counter. */
  bumpNonce(): void {
    for (let i = GCM_IV - 1; i >= GCM_IV - 8; i--) {
      this.nonce[i] = (this.nonce[i] + 1) & 0xff;
      if (this.nonce[i] !== 0) {
        break;
      }
    }
  }
}

/** Algorithms agreed in one key exchange. */
class Negotiated {
  kex: string = '';
  hostKey: string = '';
  cipherOut: string = '';
  cipherIn: string = '';
  macOut: string = '';
  macIn: string = '';
}

/** State of one key exchange in progress. */
class KexState {
  ours: Uint8Array = new Uint8Array(0);
  theirs: Uint8Array | null = null;
  algs: Negotiated = new Negotiated();
  x25519Private: Uint8Array = new Uint8Array(0);
  x25519Public: Uint8Array = new Uint8Array(0);
  dhX: bigint = BigInt(0);
  dhE: Uint8Array = new Uint8Array(0);
  /** Keys to switch to when NEWKEYS arrives. */
  pendingIn: CipherState | null = null;
  sentNewKeys: boolean = false;
}

function modPow(base: bigint, exp: bigint, mod: bigint): bigint {
  let result = BigInt(1);
  let b = base % mod;
  let e = exp;
  const zero = BigInt(0);
  const one = BigInt(1);
  while (e > zero) {
    if ((e & one) === one) {
      result = (result * b) % mod;
    }
    e = e >> one;
    b = (b * b) % mod;
  }
  return result;
}

/**
 * The SSH transport layer (RFC 4253): version exchange, binary packets with AES-GCM or
 * AES-CTR + HMAC, curve25519 / DH group 14 key exchange with host key verification, strict
 * key exchange (Terrapin fix) and re-keying in either direction. Upper layers send and receive
 * payloads of message number 5 and above.
 */
export class SshTransport {
  readonly crypto: SshCrypto;
  serverVersion: string = '';
  sessionId: Uint8Array = new Uint8Array(0);
  /** Signature algorithms the server accepts for user keys (from EXT_INFO). */
  serverSigAlgs: string[] = [];
  private stream: ByteStream;
  private verifier: HostKeyVerifier;
  private handler: (payload: Uint8Array) => void = () => {
  };
  private closeListeners: ((error: string) => void)[] = [];
  private inBuf: Uint8Array = new Uint8Array(0);
  private versionDone: boolean = false;
  private outState: CipherState = new CipherState();
  private inState: CipherState = new CipherState();
  private seqOut: number = 0;
  private seqIn: number = 0;
  private kex: KexState | null = null;
  private firstKexDone: boolean = false;
  private strict: boolean = false;
  private hostKeyBlob: Uint8Array | null = null;
  private queued: Uint8Array[] = [];
  private paused: boolean = false;
  private closed: boolean = false;
  private firstPacket: boolean = true;
  private bytesSinceKex: number = 0;
  private decryptedHead: Uint8Array | null = null;
  private ready: Promise<void>;
  private resolveReady: () => void = () => {
  };
  private rejectReady: (e: Error) => void = () => {
  };

  constructor(stream: ByteStream, crypto: SshCrypto, verifier: HostKeyVerifier) {
    this.stream = stream;
    this.crypto = crypto;
    this.verifier = verifier;
    this.ready = new Promise<void>((resolve: () => void, reject: (e: Error) => void) => {
      this.resolveReady = resolve;
      this.rejectReady = reject;
    });
  }

  /** Exchanges versions and completes the first key exchange. */
  start(): Promise<void> {
    this.stream.setOnData((d: Uint8Array) => this.onBytes(d));
    this.stream.setOnClose((err: string) => {
      if (err.length > 0) {
        this.fail(err);
      } else {
        this.fail(this.versionDone ? 'Connection closed by the server.' :
          'The server closed the connection without speaking SSH. Check the host and port.');
      }
    });
    this.stream.write(Utf8.encode(CLIENT_VERSION + '\r\n'));
    this.beginKex();
    return this.ready;
  }

  setHandler(h: (payload: Uint8Array) => void): void {
    this.handler = h;
  }

  onClose(listener: (error: string) => void): void {
    this.closeListeners.push(listener);
  }

  get isClosed(): boolean {
    return this.closed;
  }

  /** Sends a payload; held back while a key exchange is running. */
  send(payload: Uint8Array): void {
    if (this.closed) {
      return;
    }
    if (this.kex !== null && !SshTransport.isKexMessage(payload[0])) {
      this.queued.push(payload);
      return;
    }
    this.writePacket(payload);
    if (this.firstKexDone && this.kex === null && this.bytesSinceKex > REKEY_BYTES) {
      this.beginKex();
    }
  }

  /** Sends DISCONNECT and closes. `error` is what local listeners are told ('' = normal close). */
  disconnect(reason: string, error: string = ''): void {
    if (this.closed) {
      return;
    }
    try {
      // 11 = SSH_DISCONNECT_BY_APPLICATION
      this.writePacket(new ByteWriter().byte(SshMsg.DISCONNECT).u32(11).str(reason).str('').toBytes());
    } catch (e) {
      // the connection is going away anyway
    }
    this.fail(error);
  }

  // ---------- input ----------

  private onBytes(data: Uint8Array): void {
    if (this.closed) {
      return;
    }
    this.inBuf = this.inBuf.length === 0 ? data.slice() : Bytes.concat([this.inBuf, data]);
    this.pump();
  }

  private pump(): void {
    try {
      if (!this.versionDone && !this.readVersion()) {
        return;
      }
      while (!this.paused && !this.closed) {
        const payload = this.readPacket();
        if (payload === null) {
          return;
        }
        this.dispatch(payload);
      }
    } catch (e) {
      this.fail((e as Error).message);
    }
  }

  private readVersion(): boolean {
    while (true) {
      let nl = -1;
      for (let i = 0; i < this.inBuf.length; i++) {
        if (this.inBuf[i] === 10) {
          nl = i;
          break;
        }
      }
      if (nl < 0) {
        if (this.inBuf.length > MAX_VERSION_BYTES) {
          throw new SshError('The server did not send an SSH version line. Is this an SSH port?');
        }
        return false;
      }
      let line = Utf8.decode(this.inBuf.subarray(0, nl));
      this.inBuf = this.inBuf.slice(nl + 1);
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      if (line.startsWith('SSH-')) {
        if (!line.startsWith('SSH-2.0-') && !line.startsWith('SSH-1.99-')) {
          throw new SshError('Unsupported SSH protocol version: ' + line);
        }
        this.serverVersion = line;
        this.versionDone = true;
        return true;
      }
    }
  }

  /** One decrypted payload, or null when more bytes are needed. */
  private readPacket(): Uint8Array | null {
    const st = this.inState;
    const buf = this.inBuf;
    let packet: Uint8Array;
    let consumed = 0;
    if (st.mode === 'gcm' || (st.mode === 'ctr' && st.etm)) {
      if (buf.length < 4) {
        return null;
      }
      const len = Bytes.readU32(buf, 0);
      this.checkLength(len, st);
      const tail = st.mode === 'gcm' ? GCM_TAG : st.macLen;
      if (buf.length < 4 + len + tail) {
        return null;
      }
      const lenBytes = buf.subarray(0, 4);
      const body = buf.subarray(4, 4 + len);
      if (st.mode === 'gcm') {
        const gcm = st.gcm as AeadCipher;
        try {
          packet = gcm.open(st.nonce, lenBytes, buf.subarray(4, 4 + len + GCM_TAG));
        } catch (e) {
          throw new SshError('Message authentication failed (corrupted connection).');
        }
        st.bumpNonce();
      } else {
        const mac = this.crypto.hmac(st.macAlg, st.macKey, Bytes.concat([Bytes.u32(this.seqIn), lenBytes, body]));
        if (!Bytes.equal(mac, buf.subarray(4 + len, 4 + len + st.macLen))) {
          throw new SshError('Message authentication failed (corrupted connection).');
        }
        packet = (st.ctr as StreamCipher).update(body);
      }
      consumed = 4 + len + tail;
    } else if (st.mode === 'ctr') {
      if (this.decryptedHead === null) {
        if (buf.length < AES_BLOCK) {
          return null;
        }
        this.decryptedHead = (st.ctr as StreamCipher).update(buf.subarray(0, AES_BLOCK));
      }
      const head = this.decryptedHead as Uint8Array;
      const len = Bytes.readU32(head, 0);
      this.checkLength(len, st);
      if ((len + 4) % AES_BLOCK !== 0) {
        throw new SshError('Bad packet length from the server.');
      }
      if (buf.length < 4 + len + st.macLen) {
        return null;
      }
      const rest = (st.ctr as StreamCipher).update(buf.subarray(AES_BLOCK, 4 + len));
      const plain = Bytes.concat([head, rest]);
      this.decryptedHead = null;
      const mac = this.crypto.hmac(st.macAlg, st.macKey, Bytes.concat([Bytes.u32(this.seqIn), plain]));
      if (!Bytes.equal(mac, buf.subarray(4 + len, 4 + len + st.macLen))) {
        throw new SshError('Message authentication failed (corrupted connection).');
      }
      packet = plain.subarray(4);
      consumed = 4 + len + st.macLen;
    } else {
      if (buf.length < 4) {
        return null;
      }
      const len = Bytes.readU32(buf, 0);
      this.checkLength(len, st);
      if (buf.length < 4 + len) {
        return null;
      }
      packet = buf.subarray(4, 4 + len);
      consumed = 4 + len;
    }
    this.inBuf = buf.slice(consumed);
    this.seqIn = (this.seqIn + 1) >>> 0;
    this.bytesSinceKex += consumed;
    const pad = packet[0];
    if (pad < MIN_PADDING || pad + 1 > packet.length) {
      throw new SshError('Bad packet padding from the server.');
    }
    return packet.slice(1, packet.length - pad);
  }

  private checkLength(len: number, st: CipherState): void {
    if (len < 5 || len > MAX_PACKET) {
      throw new SshError('Bad packet length from the server (' + len + ').');
    }
  }

  private dispatch(p: Uint8Array): void {
    const type = p[0];
    if (this.firstPacket) {
      this.firstPacket = false;
      if (type !== SshMsg.KEXINIT) {
        throw new SshError('The server did not start key exchange.');
      }
    }
    if (this.strict && !this.firstKexDone && !SshTransport.isKexMessage(type)) {
      throw new SshError('Unexpected message during strict key exchange.');
    }
    switch (type) {
      case SshMsg.DISCONNECT: {
        const r = new ByteReader(p, 1);
        r.u32();
        const why = r.str();
        this.fail(why.length > 0 ? 'Disconnected by the server: ' + why : 'Disconnected by the server.');
        return;
      }
      case SshMsg.IGNORE:
      case SshMsg.DEBUG:
      case SshMsg.UNIMPLEMENTED:
        return;
      case SshMsg.KEXINIT:
        this.onKexInit(p);
        return;
      case SshMsg.KEX_REPLY:
        this.onKexReply(p);
        return;
      case SshMsg.NEWKEYS:
        this.onNewKeys();
        return;
      case SshMsg.EXT_INFO:
        this.onExtInfo(p);
        return;
      default:
        if (type >= SshMsg.KEXINIT && type <= 49) {
          throw new SshError('Unexpected key exchange message ' + type + '.');
        }
        this.handler(p);
    }
  }

  // ---------- output ----------

  private writePacket(payload: Uint8Array): void {
    const st = this.outState;
    const block = st.blockSize;
    const lengthCovered = st.mode === 'gcm' || st.etm ? 1 + payload.length : 5 + payload.length;
    let pad = block - (lengthCovered % block);
    if (pad < MIN_PADDING) {
      pad += block;
    }
    const len = 1 + payload.length + pad;
    const inner = new Uint8Array(len);
    inner[0] = pad;
    inner.set(payload, 1);
    inner.set(this.crypto.random(pad), 1 + payload.length);
    const lenBytes = Bytes.u32(len);
    let out: Uint8Array;
    if (st.mode === 'gcm') {
      out = Bytes.concat([lenBytes, (st.gcm as AeadCipher).seal(st.nonce, lenBytes, inner)]);
      st.bumpNonce();
    } else if (st.mode === 'ctr' && st.etm) {
      const enc = (st.ctr as StreamCipher).update(inner);
      const mac = this.crypto.hmac(st.macAlg, st.macKey, Bytes.concat([Bytes.u32(this.seqOut), lenBytes, enc]));
      out = Bytes.concat([lenBytes, enc, mac]);
    } else if (st.mode === 'ctr') {
      const plain = Bytes.concat([lenBytes, inner]);
      const mac = this.crypto.hmac(st.macAlg, st.macKey, Bytes.concat([Bytes.u32(this.seqOut), plain]));
      out = Bytes.concat([(st.ctr as StreamCipher).update(plain), mac]);
    } else {
      out = Bytes.concat([lenBytes, inner]);
    }
    this.seqOut = (this.seqOut + 1) >>> 0;
    this.bytesSinceKex += out.length;
    this.stream.write(out);
  }

  // ---------- key exchange ----------

  private static isKexMessage(type: number): boolean {
    return (type >= 1 && type <= 4) || (type >= SshMsg.KEXINIT && type <= 49);
  }

  private beginKex(): void {
    if (this.kex !== null) {
      return;
    }
    const k = new KexState();
    const kexAlgs = [KEX_CURVE25519, KEX_CURVE25519_LIBSSH, KEX_DH14];
    if (!this.firstKexDone) {
      kexAlgs.push(EXT_INFO_C, STRICT_C);
    }
    k.ours = new ByteWriter()
      .byte(SshMsg.KEXINIT)
      .raw(this.crypto.random(16))
      .nameList(kexAlgs)
      .nameList(HOST_KEY_ALGORITHMS)
      .nameList(CIPHERS).nameList(CIPHERS)
      .nameList(MACS).nameList(MACS)
      .nameList(['none']).nameList(['none'])
      .nameList([]).nameList([])
      .bool(false)
      .u32(0)
      .toBytes();
    this.kex = k;
    this.writePacket(k.ours);
  }

  private onKexInit(p: Uint8Array): void {
    if (this.kex === null) {
      this.beginKex(); // the server started a re-key
    }
    const k = this.kex as KexState;
    if (k.theirs !== null) {
      throw new SshError('The server sent KEXINIT twice.');
    }
    k.theirs = p.slice();
    const r = new ByteReader(p, 17);
    const kexS = r.nameList();
    const hostS = r.nameList();
    const encC2S = r.nameList();
    const encS2C = r.nameList();
    const macC2S = r.nameList();
    const macS2C = r.nameList();
    const compC2S = r.nameList();
    const compS2C = r.nameList();
    if (compC2S.indexOf('none') < 0 || compS2C.indexOf('none') < 0) {
      throw new SshError('The server requires compression, which is not supported.');
    }
    if (!this.firstKexDone) {
      this.strict = kexS.indexOf(STRICT_S) >= 0;
    }
    const a = k.algs;
    a.kex = SshTransport.pick([KEX_CURVE25519, KEX_CURVE25519_LIBSSH, KEX_DH14], kexS, 'key exchange');
    a.hostKey = SshTransport.pick(HOST_KEY_ALGORITHMS, hostS, 'host key');
    a.cipherOut = SshTransport.pick(CIPHERS, encC2S, 'cipher');
    a.cipherIn = SshTransport.pick(CIPHERS, encS2C, 'cipher');
    a.macOut = a.cipherOut.indexOf('gcm') >= 0 ? '' : SshTransport.pick(MACS, macC2S, 'MAC');
    a.macIn = a.cipherIn.indexOf('gcm') >= 0 ? '' : SshTransport.pick(MACS, macS2C, 'MAC');
    if (a.kex === KEX_DH14) {
      const prime = Bytes.toBigInt(Bytes.fromHex(DH14_PRIME));
      k.dhX = Bytes.toBigInt(this.crypto.random(DH_EXPONENT_BYTES));
      k.dhE = Bytes.fromBigInt(modPow(BigInt(2), k.dhX, prime));
      this.writePacket(new ByteWriter().byte(SshMsg.KEX_INIT).mpint(k.dhE).toBytes());
    } else {
      const pair = this.crypto.x25519Generate();
      k.x25519Private = pair.privateKey;
      k.x25519Public = pair.publicKey;
      this.writePacket(new ByteWriter().byte(SshMsg.KEX_INIT).bytes(pair.publicKey).toBytes());
    }
  }

  private static pick(ours: string[], theirs: string[], what: string): string {
    for (const a of ours) {
      if (theirs.indexOf(a) >= 0) {
        return a;
      }
    }
    throw new SshError(`No common ${what} algorithm with the server (it offers: ${theirs.join(', ')}).`);
  }

  private onKexReply(p: Uint8Array): void {
    const k = this.kex;
    if (k === null || k.theirs === null) {
      throw new SshError('Unexpected key exchange reply.');
    }
    const r = new ByteReader(p, 1);
    const hostKey = r.bytes().slice();
    let secret: Uint8Array;
    const h = new ByteWriter()
      .str(CLIENT_VERSION)
      .str(this.serverVersion)
      .bytes(k.ours)
      .bytes(k.theirs)
      .bytes(hostKey);
    if (k.algs.kex === KEX_DH14) {
      const f = r.mpint();
      const prime = Bytes.toBigInt(Bytes.fromHex(DH14_PRIME));
      const fv = Bytes.toBigInt(f);
      if (fv <= BigInt(1) || fv >= prime - BigInt(1)) {
        throw new SshError('Invalid Diffie-Hellman value from the server.');
      }
      secret = Bytes.fromBigInt(modPow(fv, k.dhX, prime));
      h.mpint(k.dhE).mpint(f);
    } else {
      const serverPublic = r.bytes();
      if (serverPublic.length !== 32) {
        throw new SshError('Invalid curve25519 key from the server.');
      }
      secret = this.crypto.x25519Agree(k.x25519Private, serverPublic);
      h.bytes(k.x25519Public).bytes(serverPublic);
    }
    const sig = r.bytes().slice();
    h.mpint(secret);
    const exchangeHash = this.crypto.hash(HashAlg.SHA256, h.toBytes());
    if (!SshKeys.verify(this.crypto, k.algs.hostKey, hostKey, sig, exchangeHash)) {
      throw new SshError('The server\'s host key signature is invalid.');
    }
    const finish = (): void => {
      if (this.sessionId.length === 0) {
        this.sessionId = exchangeHash;
      }
      this.hostKeyBlob = hostKey;
      this.installKeys(k, secret, exchangeHash);
    };
    if (this.hostKeyBlob !== null) {
      // Re-key: the host key must not change within a connection.
      if (!Bytes.equal(this.hostKeyBlob, hostKey)) {
        throw new SshError('The server\'s host key changed during the session.');
      }
      finish();
      return;
    }
    this.paused = true;
    const info: HostKeyInfo = {
      algorithm: SshKeys.blobType(hostKey), blob: hostKey, fingerprint: SshKeys.fingerprint(this.crypto, hostKey)
    };
    this.verifier(info).then((trusted: boolean) => {
      if (this.closed) {
        return;
      }
      if (!trusted) {
        this.disconnect('Host key not trusted', 'The host key was not trusted.');
        return;
      }
      try {
        finish();
      } catch (e) {
        this.fail((e as Error).message);
        return;
      }
      this.paused = false;
      this.pump();
    }).catch((e: Error) => this.fail(e.message));
  }

  private installKeys(k: KexState, secret: Uint8Array, hash: Uint8Array): void {
    const derive = (letter: string, len: number): Uint8Array => {
      const kEnc = new ByteWriter().mpint(secret).toBytes();
      let out = this.crypto.hash(HashAlg.SHA256,
        Bytes.concat([kEnc, hash, Utf8.encode(letter), this.sessionId]));
      while (out.length < len) {
        out = Bytes.concat([out, this.crypto.hash(HashAlg.SHA256, Bytes.concat([kEnc, hash, out]))]);
      }
      return out.slice(0, len);
    };
    const build = (cipher: string, mac: string, ivL: string, keyL: string, macL: string, encrypt: boolean): CipherState => {
      const st = new CipherState();
      const keyLen = cipher.startsWith('aes256') ? 32 : 16;
      const key = derive(keyL, keyLen);
      if (cipher.indexOf('gcm') >= 0) {
        st.mode = 'gcm';
        st.gcm = this.crypto.aesGcm(key);
        st.nonce = derive(ivL, GCM_IV);
      } else {
        st.mode = 'ctr';
        st.ctr = this.crypto.aesCtr(key, derive(ivL, AES_BLOCK), encrypt);
        st.etm = mac.endsWith('-etm@openssh.com');
        st.macAlg = mac.indexOf('512') >= 0 ? HashAlg.SHA512 : HashAlg.SHA256;
        st.macLen = st.macAlg === HashAlg.SHA512 ? 64 : 32;
        st.macKey = derive(macL, st.macLen);
      }
      return st;
    };
    k.pendingIn = build(k.algs.cipherIn, k.algs.macIn, 'B', 'D', 'F', false);
    const out = build(k.algs.cipherOut, k.algs.macOut, 'A', 'C', 'E', true);
    this.writePacket(new Uint8Array([SshMsg.NEWKEYS]));
    this.outState = out;
    if (this.strict) {
      this.seqOut = 0;
    }
    k.sentNewKeys = true;
  }

  private onNewKeys(): void {
    const k = this.kex;
    if (k === null || k.pendingIn === null || !k.sentNewKeys) {
      throw new SshError('Unexpected NEWKEYS from the server.');
    }
    this.inState = k.pendingIn;
    this.decryptedHead = null;
    if (this.strict) {
      this.seqIn = 0;
    }
    this.kex = null;
    this.bytesSinceKex = 0;
    const first = !this.firstKexDone;
    this.firstKexDone = true;
    const held = this.queued;
    this.queued = [];
    for (const q of held) {
      this.writePacket(q);
    }
    if (first) {
      this.resolveReady();
    }
  }

  private onExtInfo(p: Uint8Array): void {
    const r = new ByteReader(p, 1);
    const n = r.u32();
    for (let i = 0; i < n; i++) {
      const name = r.str();
      const value = r.bytes();
      if (name === 'server-sig-algs') {
        this.serverSigAlgs = Utf8.decode(value).split(',');
      }
    }
  }

  private fail(error: string): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    try {
      this.stream.close();
    } catch (e) {
      // already closed
    }
    this.rejectReady(sshFailure(error.length > 0 ? error : 'Connection closed.'));
    for (const l of this.closeListeners) {
      l(error);
    }
  }
}
