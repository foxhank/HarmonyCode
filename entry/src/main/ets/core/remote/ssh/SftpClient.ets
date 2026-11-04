import { ByteReader, Bytes, ByteWriter } from './Bytes';
import { SshChannel } from './SshChannel';
import { SshClient } from './SshClient';
import { SshError, sshFailure } from './SshTransport';

class Fx {
  static readonly INIT: number = 1;
  static readonly VERSION: number = 2;
  static readonly OPEN: number = 3;
  static readonly CLOSE: number = 4;
  static readonly READ: number = 5;
  static readonly WRITE: number = 6;
  static readonly LSTAT: number = 7;
  static readonly FSTAT: number = 8;
  static readonly OPENDIR: number = 11;
  static readonly READDIR: number = 12;
  static readonly REMOVE: number = 13;
  static readonly MKDIR: number = 14;
  static readonly RMDIR: number = 15;
  static readonly REALPATH: number = 16;
  static readonly STAT: number = 17;
  static readonly RENAME: number = 18;
  static readonly EXTENDED: number = 200;
  static readonly STATUS: number = 101;
  static readonly HANDLE: number = 102;
  static readonly DATA: number = 103;
  static readonly NAME: number = 104;
  static readonly ATTRS: number = 105;
}

/** SFTP status codes. */
export class SftpStatus {
  static readonly OK: number = 0;
  static readonly EOF: number = 1;
  static readonly NO_SUCH_FILE: number = 2;
  static readonly PERMISSION_DENIED: number = 3;
  static readonly FAILURE: number = 4;
}

const ATTR_SIZE: number = 0x1;
const ATTR_UIDGID: number = 0x2;
const ATTR_PERMISSIONS: number = 0x4;
const ATTR_ACMODTIME: number = 0x8;
const ATTR_EXTENDED: number = 0x80000000;
const S_IFMT: number = 0o170000;
const S_IFDIR: number = 0o040000;
const S_IFLNK: number = 0o120000;
const OPEN_READ: number = 0x1;
const OPEN_WRITE: number = 0x2;
const OPEN_CREAT: number = 0x8;
const OPEN_TRUNC: number = 0x10;
const CHUNK: number = 32 * 1024;
const PIPELINE: number = 16;
const SFTP_VERSION: number = 3;
const POSIX_RENAME: string = 'posix-rename@openssh.com';
const DIR_MODE: number = 0o755;

/** File attributes; -1 = not reported. */
export class SftpAttrs {
  size: number = -1;
  permissions: number = -1;
  mtime: number = -1;

  get isDir(): boolean {
    return this.permissions >= 0 && (this.permissions & S_IFMT) === S_IFDIR;
  }

  get isLink(): boolean {
    return this.permissions >= 0 && (this.permissions & S_IFMT) === S_IFLNK;
  }
}

export interface SftpEntry {
  name: string;
  attrs: SftpAttrs;
}

/** A failed SFTP request, with the server's status code. */
export class SftpError extends SshError {
  readonly code: number;

  constructor(code: number, message: string) {
    super(message);
    this.name = 'SftpError';
    this.code = code;
  }
}

class Pending {
  resolve: (r: ByteReader) => void;
  type: number;

  constructor(resolve: (r: ByteReader) => void) {
    this.resolve = resolve;
    this.type = 0;
  }
}

/** SFTP version 3 client (the protocol OpenSSH and Windows OpenSSH speak) over a session channel. */
export class SftpClient {
  private ch: SshChannel;
  private buf: Uint8Array = new Uint8Array(0);
  private nextId: number = 1;
  private pending: Map<number, (type: number, r: ByteReader) => void> = new Map();
  private versionWaiter: ((r: ByteReader) => void) | null = null;
  private extensions: Map<string, string> = new Map();
  private closed: boolean = false;

  private constructor(ch: SshChannel) {
    this.ch = ch;
    ch.setOnData((d: Uint8Array) => this.onData(d));
    ch.onClose(() => this.onClosed());
  }

  static async open(client: SshClient): Promise<SftpClient> {
    const ch = await client.openSession();
    const ok = await ch.subsystem('sftp');
    if (!ok) {
      ch.close();
      throw new SshError('The server has no SFTP subsystem (enable "Subsystem sftp" in sshd_config).');
    }
    const s = new SftpClient(ch);
    await s.init();
    return s;
  }

  get isClosed(): boolean {
    return this.closed;
  }

  close(): void {
    this.ch.close();
  }

  private init(): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (e: Error) => void) => {
      this.versionWaiter = (r: ByteReader) => {
        r.u32(); // version
        while (r.remaining > 0) {
          this.extensions.set(r.str(), r.str());
        }
        resolve();
      };
      this.ch.onClose(() => reject(sshFailure('The SFTP session closed during setup.')));
      this.sendRaw(new ByteWriter().byte(Fx.INIT).u32(SFTP_VERSION).toBytes());
    });
  }

  // ---------- high-level operations ----------

  async realpath(path: string): Promise<string> {
    const r = await this.expect(Fx.NAME, new ByteWriter().str(path), Fx.REALPATH, path);
    r.u32();
    return r.str();
  }

  stat(path: string): Promise<SftpAttrs> {
    return this.attrsRequest(Fx.STAT, path);
  }

  lstat(path: string): Promise<SftpAttrs> {
    return this.attrsRequest(Fx.LSTAT, path);
  }

  /** Attributes, or null when the path does not exist. */
  async statOrNull(path: string): Promise<SftpAttrs | null> {
    try {
      return await this.stat(path);
    } catch (e) {
      if (e instanceof SftpError && (e as SftpError).code === SftpStatus.NO_SUCH_FILE) {
        return null;
      }
      throw e as Error;
    }
  }

  async list(dir: string): Promise<SftpEntry[]> {
    const h = await this.handle(Fx.OPENDIR, new ByteWriter().str(dir), dir);
    const out: SftpEntry[] = [];
    try {
      while (true) {
        const reply = await this.request(Fx.READDIR, new ByteWriter().bytes(h));
        if (reply.type === Fx.STATUS) {
          const code = reply.r.u32();
          if (code === SftpStatus.EOF) {
            break;
          }
          throw SftpClient.statusError(code, reply.r, dir);
        }
        if (reply.type !== Fx.NAME) {
          throw new SshError('Unexpected SFTP reply.');
        }
        const n = reply.r.u32();
        for (let i = 0; i < n; i++) {
          const name = reply.r.str();
          reply.r.str(); // long name
          const attrs = SftpClient.readAttrs(reply.r);
          if (name !== '.' && name !== '..') {
            out.push({ name: name, attrs: attrs });
          }
        }
      }
    } finally {
      this.closeHandle(h);
    }
    return out;
  }

  /** Whole file; refuses files over `maxBytes`. Reads are pipelined. */
  async readFile(path: string, maxBytes: number): Promise<Uint8Array> {
    const h = await this.handle(Fx.OPEN, new ByteWriter().str(path).u32(OPEN_READ).u32(0), path);
    try {
      const st = await this.fstat(h);
      if (st.size > maxBytes) {
        throw new SftpError(SftpStatus.FAILURE, `${path} is too large (${Math.round(st.size / 1024)} KB).`);
      }
      const chunks: Map<number, Uint8Array> = new Map();
      let offset = 0;
      let eof = false;
      while (!eof) {
        const batch: Promise<Reply>[] = [];
        const offsets: number[] = [];
        for (let i = 0; i < PIPELINE; i++) {
          offsets.push(offset);
          batch.push(this.request(Fx.READ, new ByteWriter().bytes(h).u64(offset).u32(CHUNK)));
          offset += CHUNK;
        }
        const replies = await Promise.all(batch);
        for (let i = 0; i < replies.length; i++) {
          const rep = replies[i];
          if (rep.type === Fx.DATA) {
            const data = rep.r.bytes().slice();
            chunks.set(offsets[i], data);
            if (data.length < CHUNK) {
              // Short read (end of file, or the server caps read sizes): later chunks may not line
              // up, so drop them and continue right after this one. EOF shows up on the next read.
              for (let j = i + 1; j < offsets.length; j++) {
                chunks.delete(offsets[j]);
              }
              offset = offsets[i] + data.length;
              break;
            }
          } else if (rep.type === Fx.STATUS) {
            const code = rep.r.u32();
            if (code !== SftpStatus.EOF) {
              throw SftpClient.statusError(code, rep.r, path);
            }
            for (let j = i + 1; j < offsets.length; j++) {
              chunks.delete(offsets[j]);
            }
            eof = true;
            break;
          } else {
            throw new SshError('Unexpected SFTP reply.');
          }
        }
        if (offset > maxBytes + CHUNK * PIPELINE) {
          throw new SftpError(SftpStatus.FAILURE, `${path} is too large.`);
        }
      }
      return SftpClient.assemble(chunks);
    } finally {
      this.closeHandle(h);
    }
  }

  /** Creates or replaces a file. Writes are pipelined. */
  async writeFile(path: string, data: Uint8Array): Promise<void> {
    const h = await this.handle(Fx.OPEN,
      new ByteWriter().str(path).u32(OPEN_WRITE | OPEN_CREAT | OPEN_TRUNC).u32(0), path);
    try {
      let offset = 0;
      do {
        const batch: Promise<Reply>[] = [];
        for (let i = 0; i < PIPELINE && offset < data.length; i++) {
          const end = Math.min(data.length, offset + CHUNK);
          batch.push(this.request(Fx.WRITE, new ByteWriter().bytes(h).u64(offset).bytes(data.subarray(offset, end))));
          offset = end;
        }
        for (const rep of await Promise.all(batch)) {
          SftpClient.checkStatus(rep, path);
        }
      } while (offset < data.length);
    } finally {
      await this.closeHandleAndWait(h);
    }
  }

  async mkdir(path: string): Promise<void> {
    SftpClient.checkStatus(await this.request(Fx.MKDIR, new ByteWriter().str(path).u32(ATTR_PERMISSIONS).u32(DIR_MODE)),
      path);
  }

  async rmdir(path: string): Promise<void> {
    SftpClient.checkStatus(await this.request(Fx.RMDIR, new ByteWriter().str(path)), path);
  }

  async remove(path: string): Promise<void> {
    SftpClient.checkStatus(await this.request(Fx.REMOVE, new ByteWriter().str(path)), path);
  }

  /** Moves `from` to `to`, replacing `to` when the server supports POSIX rename. */
  async rename(from: string, to: string): Promise<void> {
    if (this.extensions.has(POSIX_RENAME)) {
      SftpClient.checkStatus(await this.request(Fx.EXTENDED, new ByteWriter().str(POSIX_RENAME).str(from).str(to)), from);
      return;
    }
    SftpClient.checkStatus(await this.request(Fx.RENAME, new ByteWriter().str(from).str(to)), from);
  }

  // ---------- plumbing ----------

  private async fstat(h: Uint8Array): Promise<SftpAttrs> {
    const rep = await this.request(Fx.FSTAT, new ByteWriter().bytes(h));
    if (rep.type === Fx.ATTRS) {
      return SftpClient.readAttrs(rep.r);
    }
    throw SftpClient.statusError(rep.type === Fx.STATUS ? rep.r.u32() : SftpStatus.FAILURE, rep.r, '');
  }

  private async attrsRequest(type: number, path: string): Promise<SftpAttrs> {
    const r = await this.expect(Fx.ATTRS, new ByteWriter().str(path), type, path);
    return SftpClient.readAttrs(r);
  }

  private async handle(type: number, body: ByteWriter, path: string): Promise<Uint8Array> {
    const r = await this.expect(Fx.HANDLE, body, type, path);
    return r.bytes().slice();
  }

  private closeHandle(h: Uint8Array): void {
    this.request(Fx.CLOSE, new ByteWriter().bytes(h)).catch(() => {
    });
  }

  private async closeHandleAndWait(h: Uint8Array): Promise<void> {
    const rep = await this.request(Fx.CLOSE, new ByteWriter().bytes(h));
    SftpClient.checkStatus(rep, '');
  }

  private async expect(replyType: number, body: ByteWriter, type: number, path: string): Promise<ByteReader> {
    const rep = await this.request(type, body);
    if (rep.type === replyType) {
      return rep.r;
    }
    if (rep.type === Fx.STATUS) {
      throw SftpClient.statusError(rep.r.u32(), rep.r, path);
    }
    throw new SshError('Unexpected SFTP reply ' + rep.type + '.');
  }

  private request(type: number, body: ByteWriter): Promise<Reply> {
    if (this.closed) {
      return Promise.reject(new SshError('The SFTP session is closed.'));
    }
    const id = this.nextId;
    this.nextId = (this.nextId + 1) >>> 0;
    const payload = Bytes.concat([new Uint8Array([type]), Bytes.u32(id), body.toBytes()]);
    return new Promise<Reply>((resolve: (r: Reply) => void) => {
      this.pending.set(id, (t: number, r: ByteReader) => resolve({ type: t, r: r }));
      this.sendRaw(payload);
    });
  }

  private sendRaw(payload: Uint8Array): void {
    this.ch.write(Bytes.concat([Bytes.u32(payload.length), payload]));
  }

  private onData(d: Uint8Array): void {
    this.buf = this.buf.length === 0 ? d : Bytes.concat([this.buf, d]);
    while (this.buf.length >= 4) {
      const len = Bytes.readU32(this.buf, 0);
      if (this.buf.length < 4 + len) {
        return;
      }
      const msg = this.buf.subarray(4, 4 + len);
      this.buf = this.buf.slice(4 + len);
      const type = msg[0];
      if (type === Fx.VERSION) {
        const w = this.versionWaiter;
        this.versionWaiter = null;
        if (w !== null) {
          w(new ByteReader(msg, 1));
        }
        continue;
      }
      const id = Bytes.readU32(msg, 1);
      const cb = this.pending.get(id);
      if (cb !== undefined) {
        this.pending.delete(id);
        cb(type, new ByteReader(msg, 5));
      }
    }
  }

  private onClosed(): void {
    this.closed = true;
    const failure = new ByteWriter().u32(SftpStatus.FAILURE).str('The SFTP session closed.').str('').toBytes();
    const ps = Array.from(this.pending.values());
    this.pending.clear();
    for (const cb of ps) {
      cb(Fx.STATUS, new ByteReader(failure));
    }
  }

  private static checkStatus(rep: Reply, path: string): void {
    if (rep.type !== Fx.STATUS) {
      throw new SshError('Unexpected SFTP reply.');
    }
    const code = rep.r.u32();
    if (code !== SftpStatus.OK) {
      throw SftpClient.statusError(code, rep.r, path);
    }
  }

  private static statusError(code: number, r: ByteReader, path: string): SftpError {
    let msg = '';
    try {
      msg = r.str();
    } catch (e) {
      msg = '';
    }
    const where = path.length > 0 ? path + ': ' : '';
    if (code === SftpStatus.NO_SUCH_FILE) {
      return new SftpError(code, where + 'no such file or folder');
    }
    if (code === SftpStatus.PERMISSION_DENIED) {
      return new SftpError(code, where + 'permission denied');
    }
    return new SftpError(code, where + (msg.length > 0 ? msg : 'SFTP error ' + code));
  }

  private static readAttrs(r: ByteReader): SftpAttrs {
    const a = new SftpAttrs();
    const flags = r.u32();
    if ((flags & ATTR_SIZE) !== 0) {
      a.size = r.u64();
    }
    if ((flags & ATTR_UIDGID) !== 0) {
      r.u32();
      r.u32();
    }
    if ((flags & ATTR_PERMISSIONS) !== 0) {
      a.permissions = r.u32();
    }
    if ((flags & ATTR_ACMODTIME) !== 0) {
      r.u32();
      a.mtime = r.u32();
    }
    if ((flags & ATTR_EXTENDED) !== 0) {
      const n = r.u32();
      for (let i = 0; i < n; i++) {
        r.str();
        r.str();
      }
    }
    return a;
  }

  private static assemble(chunks: Map<number, Uint8Array>): Uint8Array {
    const keys = Array.from(chunks.keys()).sort((a: number, b: number) => a - b);
    let end = 0;
    for (const k of keys) {
      end = Math.max(end, k + (chunks.get(k) as Uint8Array).length);
    }
    const out = new Uint8Array(end);
    for (const k of keys) {
      out.set(chunks.get(k) as Uint8Array, k);
    }
    return out;
  }
}

interface Reply {
  type: number;
  r: ByteReader;
}
