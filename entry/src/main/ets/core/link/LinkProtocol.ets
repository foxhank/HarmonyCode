import { ByteReader, ByteWriter } from '../remote/ssh/Bytes';
import { Lz4 } from './Lz4';

/** Message types (docs/desktop-link.md section 6). */
export class Msg {
  static readonly PING: number = 0x01;
  static readonly PONG: number = 0x02;
  static readonly LIST: number = 0x10;
  static readonly ENTRIES: number = 0x11;
  static readonly GET: number = 0x12;
  static readonly DATA: number = 0x13;
  static readonly PUT: number = 0x14;
  static readonly RESULT: number = 0x15;
  static readonly DELETE: number = 0x16;
  static readonly CHANGED: number = 0x17;
  static readonly EXEC: number = 0x20;
  static readonly OUTPUT: number = 0x21;
  static readonly EXIT: number = 0x22;
  static readonly KILL: number = 0x23;
  static readonly ERROR: number = 0x7f;
}

/** RESULT status codes. */
export class LinkStatus {
  static readonly OK: number = 0;
  static readonly CONFLICT: number = 1;
  static readonly REFUSED: number = 2;
  static readonly ERROR: number = 3;
}

export const PROTOCOL_VERSION: number = 1;
export const DEFAULT_PORT: number = 47110;
export const MAGIC: string = 'HCL1';
export const LABEL: string = 'HCLINK-v1';
export const MODE_PAIR: number = 1;
export const MODE_RESUME: number = 2;
export const AUTH_OK: number = 0;
export const AUTH_FAIL: number = 1;
export const HASH_LEN: number = 32;
export const ZERO_HASH: Uint8Array = new Uint8Array(HASH_LEN);
export const CHUNK_BYTES: number = 512 * 1024;
export const MAX_FILE_BYTES: number = 256 * 1024 * 1024;
export const MAX_RECORD_BYTES: number = 1024 * 1024 + 64 * 1024;
const FLAG_LZ4: number = 1;

/** A file on the desktop (or its deletion, in CHANGED events). */
export interface LinkEntry {
  path: string;
  size: number;
  mtime: number;
  hash: Uint8Array;
  deleted: boolean;
}

export class LinkMessage {
  readonly type: number;
  readonly id: number;
  readonly body: Uint8Array;

  constructor(type: number, id: number, body: Uint8Array) {
    this.type = type;
    this.id = id;
    this.body = body;
  }

  reader(): ByteReader {
    return new ByteReader(this.body);
  }
}

export class LinkCodec {
  /** `u8 type || u8 flags || u32 id || body`, compressing the body when that saves at least 1/16. */
  static encode(type: number, id: number, body: Uint8Array): Uint8Array {
    let flags = 0;
    let payload = body;
    if (body.length >= 64) {
      const packed = Lz4.compress(body);
      if (packed.length + 4 < body.length - (body.length >> 4)) {
        payload = new ByteWriter().u32(body.length).raw(packed).toBytes();
        flags |= FLAG_LZ4;
      }
    }
    return new ByteWriter().byte(type).byte(flags).u32(id).raw(payload).toBytes();
  }

  static decode(plain: Uint8Array): LinkMessage {
    const r = new ByteReader(plain);
    const type = r.byte();
    const flags = r.byte();
    const id = r.u32();
    let body = r.rest();
    if ((flags & FLAG_LZ4) !== 0) {
      const br = new ByteReader(body);
      const raw = br.u32();
      if (raw > MAX_RECORD_BYTES * 4) {
        throw new Error('Link: compressed message too large');
      }
      body = Lz4.decompress(br.rest(), raw);
    }
    return new LinkMessage(type, id, body);
  }

  static writeEntry(w: ByteWriter, e: LinkEntry): void {
    w.str(e.path).u64(e.size).u64(e.mtime).bytes(e.hash).bool(e.deleted);
  }

  static readEntry(r: ByteReader): LinkEntry {
    return { path: r.str(), size: r.u64(), mtime: r.u64(), hash: r.bytes().slice(), deleted: r.bool() };
  }

  static readEntries(r: ByteReader): LinkEntry[] {
    const n = r.u32();
    const out: LinkEntry[] = [];
    for (let i = 0; i < n; i++) {
      out.push(LinkCodec.readEntry(r));
    }
    return out;
  }

  static isZero(h: Uint8Array): boolean {
    for (let i = 0; i < h.length; i++) {
      if (h[i] !== 0) {
        return false;
      }
    }
    return true;
  }
}
