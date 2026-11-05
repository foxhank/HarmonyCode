import { CancelToken } from '../llm/CancelToken';
import { Bytes, ByteWriter, Utf8Decoder } from '../remote/ssh/Bytes';
import { HashAlg, SshCrypto } from '../remote/ssh/SshCrypto';
import { CHUNK_BYTES, LinkCodec, LinkEntry, LinkMessage, LinkStatus, MAX_FILE_BYTES, Msg } from './LinkProtocol';
import { DesktopInfo, linkFailure, LinkSession } from './LinkSession';

/** Answer to PUT / DELETE. */
export interface LinkResult {
  status: number;
  message: string;
  /** The desktop's hash of the file now (its current one on a conflict). */
  hash: Uint8Array;
}

export interface ExecResult {
  exitCode: number;
  timedOut: boolean;
}

type Handler = (m: LinkMessage) => boolean;

const PING_MS: number = 15000;
const MAX_MISSED_PINGS: number = 3;

/**
 * Requests and events over a LinkSession: file listing and transfer (chunked, hash-checked),
 * guarded writes, commands with streamed output, and CHANGED notifications.
 */
export class LinkClient {
  readonly session: LinkSession;
  private crypto: SshCrypto;
  private nextId: number = 1;
  /** Handlers by request id; one returns true when its request is complete. */
  private handlers: Map<number, Handler> = new Map();
  private eventListeners: ((entries: LinkEntry[]) => void)[] = [];
  private pingTimer: number = -1;
  private missed: number = 0;

  constructor(session: LinkSession, crypto: SshCrypto) {
    this.session = session;
    this.crypto = crypto;
    session.setOnMessage((plain: Uint8Array) => this.onPlain(plain));
    session.onClose((e: string) => this.onClosed(e));
    this.pingTimer = setInterval(() => this.ping(), PING_MS);
  }

  get info(): DesktopInfo {
    return this.session.info;
  }

  get isClosed(): boolean {
    return this.session.isClosed;
  }

  onChanged(l: (entries: LinkEntry[]) => void): void {
    this.eventListeners.push(l);
  }

  close(): void {
    this.session.close();
  }

  async list(prefix: string): Promise<LinkEntry[]> {
    const m = await this.call(Msg.LIST, new ByteWriter().str(prefix).toBytes(), Msg.ENTRIES);
    return LinkCodec.readEntries(m.reader());
  }

  /** Downloads a file and checks its hash. */
  get(path: string): Promise<Uint8Array> {
    return new Promise<Uint8Array>((resolve: (d: Uint8Array) => void, reject: (e: Error) => void) => {
      const chunks: Uint8Array[] = [];
      let received = 0;
      this.send(Msg.GET, new ByteWriter().str(path).u64(0).toBytes(), (m: LinkMessage) => {
        if (m.type === Msg.ERROR) {
          reject(linkFailure(m.reader().str()));
          return true;
        }
        const r = m.reader();
        r.str();
        const total = r.u64();
        r.u64();
        const final = r.bool();
        const hash = r.bytes().slice();
        const chunk = r.bytes().slice();
        if (total > MAX_FILE_BYTES) {
          reject(linkFailure(path + ' is too large to sync.'));
          return true;
        }
        chunks.push(chunk);
        received += chunk.length;
        if (!final) {
          return false;
        }
        const data = Bytes.concat(chunks);
        if (received !== total || !Bytes.equal(this.crypto.hash(HashAlg.SHA256, data), hash)) {
          reject(linkFailure('The download of ' + path + ' was corrupted.'));
        } else {
          resolve(data);
        }
        return true;
      });
    });
  }

  /** Uploads `data` if the desktop's file still has hash `base` (zero hash = must not exist). */
  async put(path: string, base: Uint8Array, data: Uint8Array): Promise<LinkResult> {
    const id = this.newId();
    const done = this.awaitResult(id);
    let offset = 0;
    do {
      const end = Math.min(data.length, offset + CHUNK_BYTES);
      const body = new ByteWriter().str(path).bytes(base).u64(data.length).u64(offset).bool(end >= data.length)
        .bytes(data.subarray(offset, end)).toBytes();
      this.session.write(LinkCodec.encode(Msg.PUT, id, body));
      offset = end;
    } while (offset < data.length);
    return done;
  }

  remove(path: string, base: Uint8Array): Promise<LinkResult> {
    const id = this.newId();
    const done = this.awaitResult(id);
    this.session.write(LinkCodec.encode(Msg.DELETE, id, new ByteWriter().str(path).bytes(base).toBytes()));
    return done;
  }

  /** Runs a command on the desktop, streaming its output. Cancel kills it there. */
  exec(command: string, cwd: string, timeoutMs: number, cancel: CancelToken,
    onOutput: (text: string) => void): Promise<ExecResult> {
    return new Promise<ExecResult>((resolve: (r: ExecResult) => void, reject: (e: Error) => void) => {
      const decoder = new Utf8Decoder();
      let off: () => void = () => {
      };
      const id = this.send(Msg.EXEC, new ByteWriter().str(command).str(cwd).u32(timeoutMs).toBytes(), (m: LinkMessage) => {
        if (m.type === Msg.OUTPUT) {
          onOutput(decoder.write(m.reader().bytes()));
          return false;
        }
        off();
        if (m.type === Msg.EXIT) {
          const r = m.reader();
          const code = r.u32();
          const tail = decoder.end();
          if (tail.length > 0) {
            onOutput(tail);
          }
          resolve({ exitCode: code > 0x7fffffff ? code - 0x100000000 : code, timedOut: r.bool() });
        } else {
          reject(linkFailure(m.type === Msg.ERROR ? m.reader().str() : 'Unexpected reply to a command.'));
        }
        return true;
      });
      off = cancel.onCancel(() => {
        this.session.write(LinkCodec.encode(Msg.KILL, 0, new ByteWriter().u32(id).toBytes()));
      });
    });
  }

  // ---------- plumbing ----------

  private newId(): number {
    const id = this.nextId;
    this.nextId = this.nextId >= 0x7fffffff ? 1 : this.nextId + 1;
    return id;
  }

  /** Sends a request; `handler` sees every reply until it returns true. Returns the id. */
  private send(type: number, body: Uint8Array, handler: Handler): number {
    if (this.session.isClosed) {
      handler(new LinkMessage(Msg.ERROR, 0, new ByteWriter().str('Not connected to the desktop.').toBytes()));
      return 0;
    }
    const id = this.newId();
    this.handlers.set(id, handler);
    this.session.write(LinkCodec.encode(type, id, body));
    return id;
  }

  private call(type: number, body: Uint8Array, expect: number): Promise<LinkMessage> {
    return new Promise<LinkMessage>((resolve: (m: LinkMessage) => void, reject: (e: Error) => void) => {
      this.send(type, body, (m: LinkMessage) => {
        if (m.type === expect) {
          resolve(m);
        } else {
          reject(linkFailure(m.type === Msg.ERROR ? m.reader().str() : 'Unexpected reply from the desktop.'));
        }
        return true;
      });
    });
  }

  private awaitResult(id: number): Promise<LinkResult> {
    return new Promise<LinkResult>((resolve: (r: LinkResult) => void, reject: (e: Error) => void) => {
      this.handlers.set(id, (m: LinkMessage) => {
        if (m.type === Msg.RESULT) {
          const r = m.reader();
          resolve({ status: r.byte(), message: r.str(), hash: r.bytes().slice() });
        } else {
          reject(linkFailure(m.type === Msg.ERROR ? m.reader().str() : 'Unexpected reply from the desktop.'));
        }
        return true;
      });
    });
  }

  private ping(): void {
    if (this.session.isClosed) {
      return;
    }
    this.missed++;
    if (this.missed > MAX_MISSED_PINGS) {
      this.session.close();
      return;
    }
    this.send(Msg.PING, new ByteWriter().u64(Date.now()).toBytes(), () => {
      this.missed = 0;
      return true;
    });
  }

  private onPlain(plain: Uint8Array): void {
    let m: LinkMessage;
    try {
      m = LinkCodec.decode(plain);
    } catch (e) {
      this.session.close();
      return;
    }
    this.missed = 0;
    if (m.id === 0) {
      if (m.type === Msg.CHANGED) {
        const entries = LinkCodec.readEntries(m.reader());
        for (const l of this.eventListeners) {
          l(entries);
        }
      }
      return;
    }
    const h = this.handlers.get(m.id);
    if (h !== undefined && h(m)) {
      this.handlers.delete(m.id);
    }
  }

  private onClosed(error: string): void {
    if (this.pingTimer >= 0) {
      clearInterval(this.pingTimer);
      this.pingTimer = -1;
    }
    const msg = new ByteWriter().str(error.length > 0 ? error : 'The connection to the desktop closed.').toBytes();
    const hs = Array.from(this.handlers.values());
    this.handlers.clear();
    for (const h of hs) {
      h(new LinkMessage(Msg.ERROR, 0, msg));
    }
  }

  static statusText(r: LinkResult): string {
    if (r.status === LinkStatus.OK) {
      return 'ok';
    }
    return r.message.length > 0 ? r.message : (r.status === LinkStatus.CONFLICT ? 'conflict' : 'refused');
  }
}

