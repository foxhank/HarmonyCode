// SshCrypto and SocketFactory over Node (tests only), mirroring what the app does with the system kits.
import * as crypto from 'crypto';
import * as net from 'net';
import { AeadCipher, ByteStream, Ed25519KeyPair, SocketFactory, SshCrypto, StreamCipher, X25519KeyPair }
  from '../../entry/src/main/ets/core/remote/ssh/SshCrypto';

const X25519_SPKI = Buffer.from('302a300506032b656e032100', 'hex');
const X25519_PKCS8 = Buffer.from('302e020100300506032b656e04220420', 'hex');
const ED25519_SPKI = Buffer.from('302a300506032b6570032100', 'hex');
const ED25519_PKCS8 = Buffer.from('302e020100300506032b657004220420', 'hex');

const b64url = (b: Uint8Array): string => Buffer.from(b).toString('base64url');
const u8 = (b: Buffer): Uint8Array => new Uint8Array(b.buffer, b.byteOffset, b.length).slice();

export class NodeSshCrypto implements SshCrypto {
  random(n: number): Uint8Array {
    return u8(crypto.randomBytes(n));
  }

  hash(alg: string, data: Uint8Array): Uint8Array {
    return u8(crypto.createHash(alg.toLowerCase()).update(data).digest());
  }

  hmac(alg: string, key: Uint8Array, data: Uint8Array): Uint8Array {
    return u8(crypto.createHmac(alg.toLowerCase(), key).update(data).digest());
  }

  x25519Generate(): X25519KeyPair {
    const kp = crypto.generateKeyPairSync('x25519');
    const pub = kp.publicKey.export({ format: 'der', type: 'spki' });
    const priv = kp.privateKey.export({ format: 'der', type: 'pkcs8' });
    return { publicKey: u8(pub.subarray(pub.length - 32)), privateKey: u8(priv.subarray(priv.length - 32)) };
  }

  x25519Agree(privateKey: Uint8Array, peerPublic: Uint8Array): Uint8Array {
    const priv = crypto.createPrivateKey({ key: Buffer.concat([X25519_PKCS8, privateKey]), format: 'der', type: 'pkcs8' });
    const pub = crypto.createPublicKey({ key: Buffer.concat([X25519_SPKI, peerPublic]), format: 'der', type: 'spki' });
    return u8(crypto.diffieHellman({ privateKey: priv, publicKey: pub }));
  }

  ed25519Generate(): Ed25519KeyPair {
    const kp = crypto.generateKeyPairSync('ed25519');
    const pub = kp.publicKey.export({ format: 'der', type: 'spki' });
    const priv = kp.privateKey.export({ format: 'der', type: 'pkcs8' });
    return { seed: u8(priv.subarray(priv.length - 32)), publicKey: u8(pub.subarray(pub.length - 32)) };
  }

  ed25519Sign(key: Ed25519KeyPair, data: Uint8Array): Uint8Array {
    const priv = crypto.createPrivateKey({ key: Buffer.concat([ED25519_PKCS8, key.seed]), format: 'der', type: 'pkcs8' });
    return u8(crypto.sign(null, data, priv));
  }

  ed25519Verify(publicKey: Uint8Array, signature: Uint8Array, data: Uint8Array): boolean {
    const pub = crypto.createPublicKey({ key: Buffer.concat([ED25519_SPKI, publicKey]), format: 'der', type: 'spki' });
    return crypto.verify(null, data, pub, signature);
  }

  rsaVerify(hashAlg: string, n: Uint8Array, e: Uint8Array, signature: Uint8Array, data: Uint8Array): boolean {
    const pub = crypto.createPublicKey({ key: { kty: 'RSA', n: b64url(n), e: b64url(e) }, format: 'jwk' });
    return crypto.verify(hashAlg.toLowerCase(), data, pub, signature);
  }

  ecdsaVerify(curve: string, hashAlg: string, point: Uint8Array, r: Uint8Array, s: Uint8Array, data: Uint8Array): boolean {
    const size = curve === 'P256' ? 32 : (curve === 'P384' ? 48 : 66);
    const crv = curve === 'P256' ? 'P-256' : (curve === 'P384' ? 'P-384' : 'P-521');
    const x = point.subarray(1, 1 + size);
    const y = point.subarray(1 + size);
    const pub = crypto.createPublicKey({ key: { kty: 'EC', crv: crv, x: b64url(x), y: b64url(y) }, format: 'jwk' });
    const pad = (v: Uint8Array): Buffer => Buffer.concat([Buffer.alloc(Math.max(0, size - v.length)), Buffer.from(v)]);
    return crypto.verify(hashAlg.toLowerCase(), data, { key: pub, dsaEncoding: 'ieee-p1363' }, Buffer.concat([pad(r), pad(s)]));
  }

  aesGcm(key: Uint8Array): AeadCipher {
    const alg = key.length === 32 ? 'aes-256-gcm' : 'aes-128-gcm';
    return {
      seal(nonce: Uint8Array, aad: Uint8Array, plain: Uint8Array): Uint8Array {
        const c = crypto.createCipheriv(alg, key, nonce) as crypto.CipherGCM;
        c.setAAD(aad);
        return u8(Buffer.concat([c.update(plain), c.final(), c.getAuthTag()]));
      },
      open(nonce: Uint8Array, aad: Uint8Array, ct: Uint8Array): Uint8Array {
        const d = crypto.createDecipheriv(alg, key, nonce) as crypto.DecipherGCM;
        d.setAAD(aad);
        d.setAuthTag(ct.subarray(ct.length - 16));
        return u8(Buffer.concat([d.update(ct.subarray(0, ct.length - 16)), d.final()]));
      }
    };
  }

  aesCtr(key: Uint8Array, iv: Uint8Array, encrypt: boolean): StreamCipher {
    const alg = key.length === 32 ? 'aes-256-ctr' : 'aes-128-ctr';
    const c = encrypt ? crypto.createCipheriv(alg, key, iv) : crypto.createDecipheriv(alg, key, iv);
    return { update: (d: Uint8Array): Uint8Array => u8(c.update(d)) };
  }
}

class NodeStream implements ByteStream {
  private onClose: (e: string) => void = () => {};
  private closed = false;

  constructor(private sock: net.Socket) {
    sock.on('error', (e) => this.finish(e.message));
    sock.on('close', () => this.finish(''));
  }

  private finish(e: string): void {
    if (!this.closed) {
      this.closed = true;
      this.onClose(e);
    }
  }

  write(data: Uint8Array): void {
    if (!this.closed) {
      this.sock.write(data);
    }
  }

  setOnData(l: (d: Uint8Array) => void): void {
    this.sock.on('data', (b: Buffer) => l(u8(b)));
  }

  setOnClose(l: (e: string) => void): void {
    this.onClose = l;
  }

  close(): void {
    this.sock.destroy();
  }
}

export class NodeSocketFactory implements SocketFactory {
  connect(host: string, port: number, timeoutMs: number): Promise<ByteStream> {
    return new Promise((resolve, reject) => {
      const s = net.connect({ host, port });
      const t = setTimeout(() => {
        s.destroy();
        reject(new Error('Connection timed out'));
      }, timeoutMs);
      s.once('connect', () => {
        clearTimeout(t);
        resolve(new NodeStream(s));
      });
      s.once('error', (e) => {
        clearTimeout(t);
        reject(e);
      });
    });
  }
}
