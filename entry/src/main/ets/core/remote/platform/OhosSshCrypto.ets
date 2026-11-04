import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { Bytes } from '../ssh/Bytes';
import { AeadCipher, EcCurve, Ed25519KeyPair, SshCrypto, StreamCipher, X25519KeyPair } from '../ssh/SshCrypto';

const X25519_SPKI: string = '302a300506032b656e032100';
const X25519_PKCS8: string = '302e020100300506032b656e04220420';
const ED25519_SPKI: string = '302a300506032b6570032100';
const ED25519_PKCS8: string = '302e020100300506032b657004220420';
const P256_SPKI: string = '3059301306072a8648ce3d020106082a8648ce3d030107034200';
const P384_SPKI: string = '3076301006072a8648ce3d020106052b81040022036200';
const P521_SPKI: string = '30819b301006072a8648ce3d020106052b8104002303818600';
const RAW_KEY: number = 32;
const GCM_TAG: number = 16;

function blob(data: Uint8Array): cryptoFramework.DataBlob {
  return { data: data };
}

function withPrefix(hexPrefix: string, key: Uint8Array): Uint8Array {
  return Bytes.concat([Bytes.fromHex(hexPrefix), key]);
}

function tail(data: Uint8Array, n: number): Uint8Array {
  return data.slice(data.length - n);
}

/** DER length octets. */
function derLength(n: number): Uint8Array {
  if (n < 0x80) {
    return new Uint8Array([n]);
  }
  const b = Bytes.fromBigInt(BigInt(n));
  return Bytes.concat([new Uint8Array([0x80 | b.length]), b]);
}

function derInteger(magnitude: Uint8Array): Uint8Array {
  let m = Bytes.stripZeros(magnitude);
  if ((m[0] & 0x80) !== 0) {
    m = Bytes.concat([new Uint8Array([0]), m]);
  }
  return Bytes.concat([new Uint8Array([0x02]), derLength(m.length), m]);
}

function derSequence(parts: Uint8Array[]): Uint8Array {
  const body = Bytes.concat(parts);
  return Bytes.concat([new Uint8Array([0x30]), derLength(body.length), body]);
}

/** AES-GCM over the crypto framework; a fresh cipher init per packet (new nonce each time). */
class OhosGcm implements AeadCipher {
  private key: cryptoFramework.SymKey;
  private algName: string;

  constructor(key: Uint8Array) {
    const bits = key.length * 8;
    this.algName = `AES${bits}|GCM|NoPadding`;
    this.key = cryptoFramework.createSymKeyGenerator(`AES${bits}`).convertKeySync(blob(key));
  }

  seal(nonce: Uint8Array, aad: Uint8Array, plain: Uint8Array): Uint8Array {
    const c = cryptoFramework.createCipher(this.algName);
    const spec: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec', iv: blob(nonce), aad: blob(aad), authTag: blob(new Uint8Array(GCM_TAG))
    };
    c.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, this.key, spec);
    const body = c.updateSync(blob(plain)).data;
    // In encrypt mode doFinal returns any remaining ciphertext followed by the tag.
    const fin = c.doFinalSync(null).data;
    return Bytes.concat([body, fin]);
  }

  open(nonce: Uint8Array, aad: Uint8Array, cipherAndTag: Uint8Array): Uint8Array {
    const c = cryptoFramework.createCipher(this.algName);
    const tag = cipherAndTag.slice(cipherAndTag.length - GCM_TAG);
    const spec: cryptoFramework.GcmParamsSpec = { algName: 'GcmParamsSpec', iv: blob(nonce), aad: blob(aad), authTag: blob(tag) };
    c.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, this.key, spec);
    const body = c.updateSync(blob(cipherAndTag.slice(0, cipherAndTag.length - GCM_TAG))).data;
    const fin = c.doFinalSync(null).data; // throws when the tag does not match
    return fin.length > 0 ? Bytes.concat([body, fin]) : body;
  }
}

/** AES-CTR kept initialized for the life of the connection direction. */
class OhosCtr implements StreamCipher {
  private c: cryptoFramework.Cipher;

  constructor(key: Uint8Array, iv: Uint8Array, encrypt: boolean) {
    const bits = key.length * 8;
    const k = cryptoFramework.createSymKeyGenerator(`AES${bits}`).convertKeySync(blob(key));
    this.c = cryptoFramework.createCipher(`AES${bits}|CTR|NoPadding`);
    const spec: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: blob(iv) };
    this.c.initSync(encrypt ? cryptoFramework.CryptoMode.ENCRYPT_MODE : cryptoFramework.CryptoMode.DECRYPT_MODE, k, spec);
  }

  update(data: Uint8Array): Uint8Array {
    return this.c.updateSync(blob(data)).data;
  }
}

/** SshCrypto over the HarmonyOS crypto framework (synchronous APIs, API 12+). */
export class OhosSshCrypto implements SshCrypto {
  private rng: cryptoFramework.Random = cryptoFramework.createRandom();

  random(n: number): Uint8Array {
    return this.rng.generateRandomSync(n).data;
  }

  hash(alg: string, data: Uint8Array): Uint8Array {
    const md = cryptoFramework.createMd(alg);
    md.updateSync(blob(data));
    return md.digestSync().data;
  }

  hmac(alg: string, key: Uint8Array, data: Uint8Array): Uint8Array {
    const mac = cryptoFramework.createMac(alg);
    mac.initSync(cryptoFramework.createSymKeyGenerator('HMAC').convertKeySync(blob(key)));
    mac.updateSync(blob(data));
    return mac.doFinalSync().data;
  }

  x25519Generate(): X25519KeyPair {
    const kp = cryptoFramework.createAsyKeyGenerator('X25519').generateKeyPairSync();
    return {
      publicKey: tail(kp.pubKey.getEncoded().data, RAW_KEY),
      privateKey: tail(kp.priKey.getEncoded().data, RAW_KEY)
    };
  }

  x25519Agree(privateKey: Uint8Array, peerPublic: Uint8Array): Uint8Array {
    const gen = cryptoFramework.createAsyKeyGenerator('X25519');
    const mine = gen.convertKeySync(null, blob(withPrefix(X25519_PKCS8, privateKey)));
    const theirs = gen.convertKeySync(blob(withPrefix(X25519_SPKI, peerPublic)), null);
    return cryptoFramework.createKeyAgreement('X25519').generateSecretSync(mine.priKey, theirs.pubKey).data;
  }

  ed25519Generate(): Ed25519KeyPair {
    const kp = cryptoFramework.createAsyKeyGenerator('Ed25519').generateKeyPairSync();
    return { seed: tail(kp.priKey.getEncoded().data, RAW_KEY), publicKey: tail(kp.pubKey.getEncoded().data, RAW_KEY) };
  }

  ed25519Sign(key: Ed25519KeyPair, data: Uint8Array): Uint8Array {
    const kp = cryptoFramework.createAsyKeyGenerator('Ed25519').convertKeySync(null, blob(withPrefix(ED25519_PKCS8, key.seed)));
    const s = cryptoFramework.createSign('Ed25519');
    s.initSync(kp.priKey);
    return s.signSync(blob(data)).data;
  }

  ed25519Verify(publicKey: Uint8Array, signature: Uint8Array, data: Uint8Array): boolean {
    const kp = cryptoFramework.createAsyKeyGenerator('Ed25519').convertKeySync(blob(withPrefix(ED25519_SPKI, publicKey)), null);
    return this.verifyWith('Ed25519', kp.pubKey, signature, data);
  }

  rsaVerify(hashAlg: string, n: Uint8Array, e: Uint8Array, signature: Uint8Array, data: Uint8Array): boolean {
    const common: cryptoFramework.RSACommonParamsSpec = {
      algName: 'RSA', specType: cryptoFramework.AsyKeySpecType.COMMON_PARAMS_SPEC, n: Bytes.toBigInt(n)
    };
    const spec: cryptoFramework.RSAPubKeySpec = {
      algName: 'RSA', specType: cryptoFramework.AsyKeySpecType.PUBLIC_KEY_SPEC, params: common, pk: Bytes.toBigInt(e)
    };
    const pub = cryptoFramework.createAsyKeyGeneratorBySpec(spec).generatePubKeySync();
    return this.verifyWith(`RSA|PKCS1|${hashAlg}`, pub, signature, data);
  }

  ecdsaVerify(curve: string, hashAlg: string, point: Uint8Array, r: Uint8Array, s: Uint8Array, data: Uint8Array): boolean {
    let prefix = P256_SPKI;
    let gen = 'ECC256';
    if (curve === EcCurve.P384) {
      prefix = P384_SPKI;
      gen = 'ECC384';
    } else if (curve === EcCurve.P521) {
      prefix = P521_SPKI;
      gen = 'ECC521';
    }
    const kp = cryptoFramework.createAsyKeyGenerator(gen).convertKeySync(blob(withPrefix(prefix, point)), null);
    const der = derSequence([derInteger(r), derInteger(s)]);
    return this.verifyWith(`${gen}|${hashAlg}`, kp.pubKey, der, data);
  }

  aesGcm(key: Uint8Array): AeadCipher {
    return new OhosGcm(key);
  }

  aesCtr(key: Uint8Array, iv: Uint8Array, encrypt: boolean): StreamCipher {
    return new OhosCtr(key, iv, encrypt);
  }

  private verifyWith(alg: string, pub: cryptoFramework.PubKey, signature: Uint8Array, data: Uint8Array): boolean {
    try {
      const v = cryptoFramework.createVerify(alg);
      v.initSync(pub);
      return v.verifySync(blob(data), blob(signature));
    } catch (e) {
      return false;
    }
  }
}
