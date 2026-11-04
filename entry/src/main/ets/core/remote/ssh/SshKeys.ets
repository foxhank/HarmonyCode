import { Base64, ByteReader, Bytes, ByteWriter, Utf8 } from './Bytes';
import { EcCurve, Ed25519KeyPair, HashAlg, SshCrypto } from './SshCrypto';

export class SshKeyError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SshKeyError';
  }
}

/** Host key algorithms we accept, in preference order. */
export const HOST_KEY_ALGORITHMS: string[] = ['ssh-ed25519', 'ecdsa-sha2-nistp256', 'ecdsa-sha2-nistp384',
  'ecdsa-sha2-nistp521', 'rsa-sha2-512', 'rsa-sha2-256'];

const ED25519: string = 'ssh-ed25519';
const PEM_BEGIN: string = '-----BEGIN OPENSSH PRIVATE KEY-----';
const PEM_END: string = '-----END OPENSSH PRIVATE KEY-----';
const AUTH_MAGIC: string = 'openssh-key-v1';
const PEM_LINE: number = 70;
const CIPHER_BLOCK: number = 8;

/** The user's key for public-key authentication. */
export interface UserKey {
  pair: Ed25519KeyPair;
  comment: string;
}

/** Signature checks and key encodings. */
export class SshKeys {
  /** "SHA256:<base64>" as printed by ssh-keygen -l. */
  static fingerprint(crypto: SshCrypto, blob: Uint8Array): string {
    return 'SHA256:' + Base64.encode(crypto.hash(HashAlg.SHA256, blob)).replace(new RegExp('=+$'), '');
  }

  /** Key type name inside a public key blob. */
  static blobType(blob: Uint8Array): string {
    return new ByteReader(blob).str();
  }

  /**
   * Verifies `sigBlob` (string algorithm, string signature) over `data` with the host key
   * `keyBlob`. `negotiated` is the host key algorithm agreed in key exchange.
   */
  static verify(crypto: SshCrypto, negotiated: string, keyBlob: Uint8Array, sigBlob: Uint8Array,
    data: Uint8Array): boolean {
    const key = new ByteReader(keyBlob);
    const keyType = key.str();
    const sig = new ByteReader(sigBlob);
    const sigAlg = sig.str();
    const sigBytes = sig.bytes();
    if (sigAlg !== negotiated) {
      return false;
    }
    if (keyType === ED25519) {
      return crypto.ed25519Verify(key.bytes(), sigBytes, data);
    }
    if (keyType === 'ssh-rsa') {
      const e = key.mpint();
      const n = key.mpint();
      if (sigAlg === 'rsa-sha2-512') {
        return crypto.rsaVerify(HashAlg.SHA512, n, e, sigBytes, data);
      }
      if (sigAlg === 'rsa-sha2-256') {
        return crypto.rsaVerify(HashAlg.SHA256, n, e, sigBytes, data);
      }
      return false;
    }
    if (keyType.startsWith('ecdsa-sha2-')) {
      key.str(); // curve identifier, repeated
      const point = key.bytes();
      const rs = new ByteReader(sigBytes);
      const r = rs.mpint();
      const s = rs.mpint();
      if (keyType === 'ecdsa-sha2-nistp256') {
        return crypto.ecdsaVerify(EcCurve.P256, HashAlg.SHA256, point, r, s, data);
      }
      if (keyType === 'ecdsa-sha2-nistp384') {
        return crypto.ecdsaVerify(EcCurve.P384, HashAlg.SHA384, point, r, s, data);
      }
      if (keyType === 'ecdsa-sha2-nistp521') {
        return crypto.ecdsaVerify(EcCurve.P521, HashAlg.SHA512, point, r, s, data);
      }
    }
    return false;
  }

  /** Public key blob of an Ed25519 key. */
  static ed25519Blob(publicKey: Uint8Array): Uint8Array {
    return new ByteWriter().str(ED25519).bytes(publicKey).toBytes();
  }

  /** Signature blob for user authentication. */
  static ed25519Signature(crypto: SshCrypto, key: Ed25519KeyPair, data: Uint8Array): Uint8Array {
    return new ByteWriter().str(ED25519).bytes(crypto.ed25519Sign(key, data)).toBytes();
  }

  /** "ssh-ed25519 AAAA... comment", the line that goes into ~/.ssh/authorized_keys. */
  static publicKeyLine(key: UserKey): string {
    const line = ED25519 + ' ' + Base64.encode(SshKeys.ed25519Blob(key.pair.publicKey));
    return key.comment.length > 0 ? line + ' ' + key.comment : line;
  }

  static generate(crypto: SshCrypto, comment: string): UserKey {
    return { pair: crypto.ed25519Generate(), comment: comment };
  }

  /** Serializes to the unencrypted OpenSSH private key format (what ssh-keygen writes). */
  static toOpenSsh(crypto: SshCrypto, key: UserKey): string {
    const check = Bytes.readU32(crypto.random(4), 0);
    const priv = new ByteWriter()
      .u32(check).u32(check)
      .str(ED25519)
      .bytes(key.pair.publicKey)
      .bytes(Bytes.concat([key.pair.seed, key.pair.publicKey]))
      .str(key.comment);
    for (let pad = 1; priv.length % CIPHER_BLOCK !== 0; pad++) {
      priv.byte(pad);
    }
    const body = new ByteWriter()
      .raw(Utf8.encode(AUTH_MAGIC)).byte(0)
      .str('none').str('none').str('')
      .u32(1)
      .bytes(SshKeys.ed25519Blob(key.pair.publicKey))
      .bytes(priv.toBytes())
      .toBytes();
    const b64 = Base64.encode(body);
    const lines: string[] = [PEM_BEGIN];
    for (let i = 0; i < b64.length; i += PEM_LINE) {
      lines.push(b64.substring(i, i + PEM_LINE));
    }
    lines.push(PEM_END);
    return lines.join('\n') + '\n';
  }

  /** Parses an unencrypted OpenSSH Ed25519 private key. Throws SshKeyError with a reason. */
  static fromOpenSsh(text: string): UserKey {
    const start = text.indexOf(PEM_BEGIN);
    const end = text.indexOf(PEM_END);
    if (start < 0 || end < 0) {
      throw new SshKeyError('Not an OpenSSH private key (expected "' + PEM_BEGIN + '").');
    }
    const body = Base64.decode(text.substring(start + PEM_BEGIN.length, end));
    const magic = Utf8.encode(AUTH_MAGIC);
    if (body.length < magic.length + 1 || !Bytes.equal(body.subarray(0, magic.length), magic)) {
      throw new SshKeyError('Unrecognized private key data.');
    }
    const r = new ByteReader(body, magic.length + 1);
    const cipher = r.str();
    r.str(); // kdf name
    r.bytes(); // kdf options
    if (cipher !== 'none') {
      throw new SshKeyError('The key is protected by a passphrase. Remove it with "ssh-keygen -p -N \'\' -f <key>" ' +
        'or generate a key in HarmonyCode.');
    }
    if (r.u32() !== 1) {
      throw new SshKeyError('Files with several keys are not supported.');
    }
    r.bytes(); // public key blob
    const p = new ByteReader(r.bytes());
    if (p.u32() !== p.u32()) {
      throw new SshKeyError('The private key is corrupt.');
    }
    const type = p.str();
    if (type !== ED25519) {
      throw new SshKeyError('Only Ed25519 keys are supported (this key is ' + type + '). Create one with ' +
        '"ssh-keygen -t ed25519" or in HarmonyCode.');
    }
    const pub = p.bytes();
    const secret = p.bytes();
    const comment = p.str();
    if (pub.length !== 32 || secret.length !== 64) {
      throw new SshKeyError('The private key is corrupt.');
    }
    return { pair: { seed: secret.slice(0, 32), publicKey: pub.slice() }, comment: comment };
  }
}
