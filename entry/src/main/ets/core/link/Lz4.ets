const MIN_MATCH: number = 4;
/** The block format's end rules: the last 5 bytes are literals; the last match starts 12+ bytes before the end. */
const LAST_LITERALS: number = 5;
const MF_LIMIT: number = 12;
const HASH_BITS: number = 16;
const MAX_OFFSET: number = 65535;

function read32(b: Uint8Array, i: number): number {
  return (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)) >>> 0;
}

function hash32(v: number): number {
  return (Math.imul(v, 2654435761) >>> (32 - HASH_BITS)) >>> 0;
}

/** A growable byte buffer. */
class Out {
  buf: Uint8Array;
  len: number = 0;

  constructor(cap: number) {
    this.buf = new Uint8Array(Math.max(16, cap));
  }

  ensure(n: number): void {
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

  byte(v: number): void {
    this.ensure(1);
    this.buf[this.len++] = v;
  }

  bytes(src: Uint8Array, from: number, to: number): void {
    this.ensure(to - from);
    this.buf.set(src.subarray(from, to), this.len);
    this.len += to - from;
  }

  /** Length continuation bytes after a 15 in the token. */
  length(n: number): void {
    let v = n;
    while (v >= 255) {
      this.byte(255);
      v -= 255;
    }
    this.byte(v);
  }
}

/**
 * LZ4 block format (lz4.org), the compression of HarmonyCode Link messages. Greedy matching with
 * a 64K-entry hash table: fast and simple, ratios close to the reference "fast" mode on source code.
 */
export class Lz4 {
  static compress(src: Uint8Array): Uint8Array {
    const n = src.length;
    const out = new Out(n + Math.floor(n / 255) + 16);
    const table = new Int32Array(1 << HASH_BITS).fill(-1);
    let anchor = 0;
    let i = 0;
    const matchLimit = n - MF_LIMIT;
    while (i < matchLimit) {
      const seq = read32(src, i);
      const h = hash32(seq);
      const ref = table[h];
      table[h] = i;
      if (ref < 0 || i - ref > MAX_OFFSET || read32(src, ref) !== seq) {
        i++;
        continue;
      }
      // Extend the match (not into the last literals).
      let len = MIN_MATCH;
      const end = n - LAST_LITERALS;
      while (i + len < end && src[ref + len] === src[i + len]) {
        len++;
      }
      Lz4.sequence(out, src, anchor, i, i - ref, len);
      i += len;
      anchor = i;
      if (i < matchLimit) {
        table[hash32(read32(src, i - 2))] = i - 2;
      }
    }
    // Final literals.
    const lit = n - anchor;
    out.byte(Math.min(lit, 15) << 4);
    if (lit >= 15) {
      out.length(lit - 15);
    }
    out.bytes(src, anchor, n);
    return out.buf.slice(0, out.len);
  }

  private static sequence(out: Out, src: Uint8Array, anchor: number, at: number, offset: number, matchLen: number): void {
    const lit = at - anchor;
    const ml = matchLen - MIN_MATCH;
    out.byte((Math.min(lit, 15) << 4) | Math.min(ml, 15));
    if (lit >= 15) {
      out.length(lit - 15);
    }
    out.bytes(src, anchor, at);
    out.byte(offset & 0xff);
    out.byte(offset >> 8);
    if (ml >= 15) {
      out.length(ml - 15);
    }
  }

  /** Decompresses a block whose original size is `rawLength`. Throws on malformed input. */
  static decompress(src: Uint8Array, rawLength: number): Uint8Array {
    const dst = new Uint8Array(rawLength);
    let s = 0;
    let d = 0;
    while (s < src.length) {
      const token = src[s++];
      let lit = token >> 4;
      if (lit === 15) {
        let b = 255;
        while (b === 255) {
          if (s >= src.length) {
            throw new Error('LZ4: truncated literal length');
          }
          b = src[s++];
          lit += b;
        }
      }
      if (s + lit > src.length || d + lit > rawLength) {
        throw new Error('LZ4: literals overrun');
      }
      dst.set(src.subarray(s, s + lit), d);
      s += lit;
      d += lit;
      if (s >= src.length) {
        break; // the last sequence has no match
      }
      if (s + 2 > src.length) {
        throw new Error('LZ4: truncated offset');
      }
      const offset = src[s] | (src[s + 1] << 8);
      s += 2;
      if (offset === 0 || offset > d) {
        throw new Error('LZ4: bad offset');
      }
      let ml = token & 15;
      if (ml === 15) {
        let b = 255;
        while (b === 255) {
          if (s >= src.length) {
            throw new Error('LZ4: truncated match length');
          }
          b = src[s++];
          ml += b;
        }
      }
      ml += MIN_MATCH;
      if (d + ml > rawLength) {
        throw new Error('LZ4: match overrun');
      }
      // Byte by byte: matches may overlap their own output.
      let m = d - offset;
      for (let k = 0; k < ml; k++) {
        dst[d++] = dst[m++];
      }
    }
    if (d !== rawLength) {
      throw new Error('LZ4: size mismatch');
    }
    return dst;
  }
}
