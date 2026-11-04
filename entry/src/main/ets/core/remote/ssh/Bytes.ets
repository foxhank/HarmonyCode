/** Byte helpers for the SSH wire format (RFC 4251 section 5). Platform-free. */
export class Bytes {
  static concat(parts: Uint8Array[]): Uint8Array {
    let n = 0;
    for (const p of parts) {
      n += p.length;
    }
    const out = new Uint8Array(n);
    let o = 0;
    for (const p of parts) {
      out.set(p, o);
      o += p.length;
    }
    return out;
  }

  static equal(a: Uint8Array, b: Uint8Array): boolean {
    if (a.length !== b.length) {
      return false;
    }
    let diff = 0;
    for (let i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff === 0;
  }

  static u32(n: number): Uint8Array {
    const b = new Uint8Array(4);
    b[0] = (n >>> 24) & 0xff;
    b[1] = (n >>> 16) & 0xff;
    b[2] = (n >>> 8) & 0xff;
    b[3] = n & 0xff;
    return b;
  }

  static readU32(b: Uint8Array, o: number): number {
    return ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) >>> 0;
  }

  static hex(b: Uint8Array): string {
    let s = '';
    for (let i = 0; i < b.length; i++) {
      s += (b[i] < 16 ? '0' : '') + b[i].toString(16);
    }
    return s;
  }

  static fromHex(hex: string): Uint8Array {
    const clean = hex.replace(new RegExp('\\s+', 'g'), '');
    const out = new Uint8Array(clean.length / 2);
    for (let i = 0; i < out.length; i++) {
      out[i] = parseInt(clean.substring(i * 2, i * 2 + 2), 16);
    }
    return out;
  }

  /** Big-endian unsigned bytes -> bigint. */
  static toBigInt(b: Uint8Array): bigint {
    let v = BigInt(0);
    const eight = BigInt(8);
    for (let i = 0; i < b.length; i++) {
      v = (v << eight) | BigInt(b[i]);
    }
    return v;
  }

  /** bigint -> minimal big-endian unsigned bytes (at least one byte), or exactly `len` bytes. */
  static fromBigInt(v: bigint, len: number = 0): Uint8Array {
    const out: number[] = [];
    let x = v;
    const zero = BigInt(0);
    const ff = BigInt(255);
    const eight = BigInt(8);
    while (x > zero) {
      out.unshift(Number(x & ff));
      x = x >> eight;
    }
    while (out.length < len || out.length === 0) {
      out.unshift(0);
    }
    return new Uint8Array(out);
  }

  /** Strips leading zero bytes (keeps at least one). */
  static stripZeros(b: Uint8Array): Uint8Array {
    let i = 0;
    while (i < b.length - 1 && b[i] === 0) {
      i++;
    }
    return b.subarray(i);
  }
}

/** UTF-8 codec (no platform TextEncoder in core code). */
export class Utf8 {
  static encode(s: string): Uint8Array {
    const out: number[] = [];
    for (let i = 0; i < s.length; i++) {
      let c = s.charCodeAt(i);
      if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
        const d = s.charCodeAt(i + 1);
        if (d >= 0xdc00 && d <= 0xdfff) {
          c = 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00);
          i++;
        }
      }
      if (c < 0x80) {
        out.push(c);
      } else if (c < 0x800) {
        out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
      } else if (c < 0x10000) {
        out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
      } else {
        out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
      }
    }
    return new Uint8Array(out);
  }

  static decode(b: Uint8Array): string {
    const d = new Utf8Decoder();
    return d.write(b) + d.end();
  }
}

/** Streaming UTF-8 decoder: keeps an incomplete trailing sequence for the next chunk. */
export class Utf8Decoder {
  private carry: number[] = [];

  write(chunk: Uint8Array): string {
    const b: number[] = this.carry.slice();
    for (let i = 0; i < chunk.length; i++) {
      b.push(chunk[i]);
    }
    this.carry = [];
    const parts: string[] = [];
    let codes: number[] = [];
    let i = 0;
    while (i < b.length) {
      const c = b[i];
      let need = 0;
      let cp = 0;
      if (c < 0x80) {
        cp = c;
      } else if ((c & 0xe0) === 0xc0) {
        need = 1;
        cp = c & 0x1f;
      } else if ((c & 0xf0) === 0xe0) {
        need = 2;
        cp = c & 0x0f;
      } else if ((c & 0xf8) === 0xf0) {
        need = 3;
        cp = c & 0x07;
      } else {
        codes.push(0xfffd);
        i++;
        continue;
      }
      if (need > 0 && i + need >= b.length) {
        // The sequence may continue in the next chunk: keep it if what we have is well-formed.
        let valid = true;
        for (let k = i + 1; k < b.length; k++) {
          if ((b[k] & 0xc0) !== 0x80) {
            valid = false;
          }
        }
        if (valid) {
          this.carry = b.slice(i);
          break;
        }
      }
      let ok = true;
      for (let k = 1; k <= need; k++) {
        const n = b[i + k];
        if (n === undefined || (n & 0xc0) !== 0x80) {
          ok = false;
          break;
        }
        cp = (cp << 6) | (n & 0x3f);
      }
      if (!ok) {
        codes.push(0xfffd);
        i++;
        continue;
      }
      i += need + 1;
      if (cp >= 0x10000) {
        cp -= 0x10000;
        codes.push(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff));
      } else {
        codes.push(cp);
      }
      if (codes.length >= 4096) {
        parts.push(String.fromCharCode(...codes));
        codes = [];
      }
    }
    if (codes.length > 0) {
      parts.push(String.fromCharCode(...codes));
    }
    return parts.join('');
  }

  /** Flushes an incomplete sequence as a replacement character. */
  end(): string {
    const had = this.carry.length > 0;
    this.carry = [];
    return had ? '�' : '';
  }
}

const B64: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

export class Base64 {
  static encode(b: Uint8Array): string {
    let s = '';
    for (let i = 0; i < b.length; i += 3) {
      const n = (b[i] << 16) | ((i + 1 < b.length ? b[i + 1] : 0) << 8) | (i + 2 < b.length ? b[i + 2] : 0);
      s += B64.charAt((n >> 18) & 63) + B64.charAt((n >> 12) & 63) +
        (i + 1 < b.length ? B64.charAt((n >> 6) & 63) : '=') + (i + 2 < b.length ? B64.charAt(n & 63) : '=');
    }
    return s;
  }

  static decode(text: string): Uint8Array {
    const s = text.replace(new RegExp('[^A-Za-z0-9+/]', 'g'), '');
    const out: number[] = [];
    let buf = 0;
    let bits = 0;
    for (let i = 0; i < s.length; i++) {
      buf = (buf << 6) | B64.indexOf(s.charAt(i));
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out.push((buf >> bits) & 0xff);
      }
    }
    return new Uint8Array(out);
  }
}

/** Builds SSH wire data. */
export class ByteWriter {
  private buf: Uint8Array = new Uint8Array(256);
  private len: number = 0;

  private ensure(n: number): void {
    if (this.len + n <= this.buf.length) {
      return;
    }
    let cap = this.buf.length * 2;
    while (cap < this.len + n) {
      cap *= 2;
    }
    const next = new Uint8Array(cap);
    next.set(this.buf.subarray(0, this.len));
    this.buf = next;
  }

  byte(v: number): ByteWriter {
    this.ensure(1);
    this.buf[this.len++] = v & 0xff;
    return this;
  }

  bool(v: boolean): ByteWriter {
    return this.byte(v ? 1 : 0);
  }

  u32(v: number): ByteWriter {
    this.ensure(4);
    this.buf.set(Bytes.u32(v), this.len);
    this.len += 4;
    return this;
  }

  u64(v: number): ByteWriter {
    const hi = Math.floor(v / 0x100000000);
    return this.u32(hi).u32(v >>> 0);
  }

  raw(b: Uint8Array): ByteWriter {
    this.ensure(b.length);
    this.buf.set(b, this.len);
    this.len += b.length;
    return this;
  }

  /** Length-prefixed bytes. */
  bytes(b: Uint8Array): ByteWriter {
    return this.u32(b.length).raw(b);
  }

  /** Length-prefixed UTF-8 text. */
  str(s: string): ByteWriter {
    return this.bytes(Utf8.encode(s));
  }

  /** Unsigned big-endian magnitude as an SSH mpint. */
  mpint(magnitude: Uint8Array): ByteWriter {
    const m = Bytes.stripZeros(magnitude);
    if (m.length === 1 && m[0] === 0) {
      return this.u32(0);
    }
    if ((m[0] & 0x80) !== 0) {
      return this.u32(m.length + 1).byte(0).raw(m);
    }
    return this.bytes(m);
  }

  nameList(names: string[]): ByteWriter {
    return this.str(names.join(','));
  }

  get length(): number {
    return this.len;
  }

  toBytes(): Uint8Array {
    return this.buf.slice(0, this.len);
  }
}

export class SshFormatError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SshFormatError';
  }
}

/** Reads SSH wire data. Throws SshFormatError past the end. */
export class ByteReader {
  private b: Uint8Array;
  private o: number = 0;

  constructor(b: Uint8Array, offset: number = 0) {
    this.b = b;
    this.o = offset;
  }

  private need(n: number): void {
    if (this.o + n > this.b.length) {
      throw new SshFormatError('Truncated SSH data');
    }
  }

  get remaining(): number {
    return this.b.length - this.o;
  }

  byte(): number {
    this.need(1);
    return this.b[this.o++];
  }

  bool(): boolean {
    return this.byte() !== 0;
  }

  u32(): number {
    this.need(4);
    const v = Bytes.readU32(this.b, this.o);
    this.o += 4;
    return v;
  }

  u64(): number {
    const hi = this.u32();
    const lo = this.u32();
    return hi * 0x100000000 + lo;
  }

  raw(n: number): Uint8Array {
    this.need(n);
    const v = this.b.subarray(this.o, this.o + n);
    this.o += n;
    return v;
  }

  bytes(): Uint8Array {
    return this.raw(this.u32());
  }

  str(): string {
    return Utf8.decode(this.bytes());
  }

  /** mpint as unsigned magnitude (positive values only, as SSH uses them). */
  mpint(): Uint8Array {
    const v = this.bytes();
    return v.length === 0 ? new Uint8Array([0]) : Bytes.stripZeros(v);
  }

  nameList(): string[] {
    const s = this.str();
    return s.length === 0 ? [] : s.split(',');
  }

  rest(): Uint8Array {
    const v = this.b.subarray(this.o);
    this.o = this.b.length;
    return v;
  }
}
