/** A raw X25519 key pair (32-byte keys). */
export interface X25519KeyPair {
  publicKey: Uint8Array;
  privateKey: Uint8Array;
}

/** A raw Ed25519 key pair: 32-byte seed and 32-byte public key. */
export interface Ed25519KeyPair {
  seed: Uint8Array;
  publicKey: Uint8Array;
}

/** AES-GCM with a fresh nonce per packet. `open` throws when the tag does not match. */
export interface AeadCipher {
  /** Returns ciphertext followed by the 16-byte tag. */
  seal(nonce: Uint8Array, aad: Uint8Array, plain: Uint8Array): Uint8Array;
  open(nonce: Uint8Array, aad: Uint8Array, cipherAndTag: Uint8Array): Uint8Array;
}

/** A stateful stream cipher (AES-CTR): each call continues the key stream. */
export interface StreamCipher {
  update(data: Uint8Array): Uint8Array;
}

/** Hash algorithm names used by SSH. */
export class HashAlg {
  static readonly SHA1: string = 'SHA1';
  static readonly SHA256: string = 'SHA256';
  static readonly SHA384: string = 'SHA384';
  static readonly SHA512: string = 'SHA512';
}

/** Named curves for ECDSA host keys. */
export class EcCurve {
  static readonly P256: string = 'P256';
  static readonly P384: string = 'P384';
  static readonly P521: string = 'P521';
}

/**
 * The primitives the SSH client needs, all synchronous. The app implements them with the
 * system crypto framework; tests implement them with Node's crypto. Everything else (packet
 * format, key exchange, key derivation, authentication) is platform-free code on top.
 */
export interface SshCrypto {
  random(n: number): Uint8Array;
  hash(alg: string, data: Uint8Array): Uint8Array;
  hmac(alg: string, key: Uint8Array, data: Uint8Array): Uint8Array;
  x25519Generate(): X25519KeyPair;
  x25519Agree(privateKey: Uint8Array, peerPublic: Uint8Array): Uint8Array;
  ed25519Generate(): Ed25519KeyPair;
  ed25519Sign(key: Ed25519KeyPair, data: Uint8Array): Uint8Array;
  ed25519Verify(publicKey: Uint8Array, signature: Uint8Array, data: Uint8Array): boolean;
  /** RSASSA-PKCS1-v1_5. `n` and `e` are unsigned big-endian magnitudes. */
  rsaVerify(hashAlg: string, n: Uint8Array, e: Uint8Array, signature: Uint8Array, data: Uint8Array): boolean;
  /** `point` is the uncompressed public point (0x04 || X || Y); r and s are unsigned magnitudes. */
  ecdsaVerify(curve: string, hashAlg: string, point: Uint8Array, r: Uint8Array, s: Uint8Array,
    data: Uint8Array): boolean;
  aesGcm(key: Uint8Array): AeadCipher;
  aesCtr(key: Uint8Array, iv: Uint8Array, encrypt: boolean): StreamCipher;
}

/** A bidirectional byte stream (a TCP socket, or an SSH channel for jump hosts). */
export interface ByteStream {
  write(data: Uint8Array): void;
  /** Called with each received chunk. */
  setOnData(listener: (data: Uint8Array) => void): void;
  /** Called once when the stream ends; `error` is '' for a clean close. */
  setOnClose(listener: (error: string) => void): void;
  close(): void;
}

/** Opens TCP connections. */
export interface SocketFactory {
  connect(host: string, port: number, timeoutMs: number): Promise<ByteStream>;
}
