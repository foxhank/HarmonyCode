import { connection, socket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Bytes } from '../ssh/Bytes';
import { ByteStream, SocketFactory } from '../ssh/SshCrypto';

const FAMILY_V4: number = 1;
const FAMILY_V6: number = 2;
const IPV4: RegExp = new RegExp('^\\d{1,3}(\\.\\d{1,3}){3}$');

function message(e: Object): string {
  const b = e as BusinessError;
  return b.message !== undefined && b.message.length > 0 ? b.message : 'network error ' + b.code;
}

/** A TCP socket as a ByteStream. Writes go out one at a time, in order. */
class OhosTcpStream implements ByteStream {
  private tcp: socket.TCPSocket;
  private queue: Uint8Array[] = [];
  private sending: boolean = false;
  private closed: boolean = false;
  private onClose: (error: string) => void = () => {
  };

  constructor(tcp: socket.TCPSocket) {
    this.tcp = tcp;
    tcp.on('close', () => this.finish(''));
    tcp.on('error', (e: BusinessError) => this.finish(message(e)));
  }

  write(data: Uint8Array): void {
    if (this.closed) {
      return;
    }
    this.queue.push(data);
    this.pump();
  }

  setOnData(listener: (data: Uint8Array) => void): void {
    this.tcp.on('message', (m: socket.SocketMessageInfo) => listener(new Uint8Array(m.message)));
  }

  setOnClose(listener: (error: string) => void): void {
    this.onClose = listener;
  }

  close(): void {
    if (this.closed) {
      return;
    }
    this.tcp.close().catch(() => {
    });
    this.finish('');
  }

  private pump(): void {
    if (this.sending || this.queue.length === 0 || this.closed) {
      return;
    }
    // Coalesce everything queued into one send.
    const data = this.queue.length === 1 ? this.queue[0] : Bytes.concat(this.queue);
    this.queue = [];
    this.sending = true;
    const buf = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength) as ArrayBuffer;
    this.tcp.send({ data: buf }).then(() => {
      this.sending = false;
      this.pump();
    }).catch((e: BusinessError) => {
      this.sending = false;
      this.finish(message(e));
    });
  }

  private finish(error: string): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    try {
      this.tcp.off('message');
      this.tcp.off('close');
      this.tcp.off('error');
    } catch (e) {
      // already released
    }
    this.onClose(error);
  }
}

/** Opens TCP connections with the system network kit, resolving host names first. */
export class OhosSockets implements SocketFactory {
  async connect(host: string, port: number, timeoutMs: number): Promise<ByteStream> {
    const address = await OhosSockets.resolve(host);
    const tcp = socket.constructTCPSocketInstance();
    try {
      await tcp.connect({ address: { address: address.address, port: port, family: address.family }, timeout: timeoutMs });
    } catch (e) {
      tcp.close().catch(() => {
      });
      throw new Error(`Cannot connect to ${host}:${port}: ${message(e as Object)}`);
    }
    return new OhosTcpStream(tcp);
  }

  private static async resolve(host: string): Promise<connection.NetAddress> {
    const h = host.trim();
    if (IPV4.test(h)) {
      return { address: h, family: FAMILY_V4 };
    }
    if (h.indexOf(':') >= 0) {
      return { address: h.replace(new RegExp('^\\[|\\]$', 'g'), ''), family: FAMILY_V6 };
    }
    let found: connection.NetAddress[] = [];
    try {
      found = await connection.getAddressesByName(h);
    } catch (e) {
      throw new Error(`Cannot resolve host name "${h}": ${message(e as Object)}`);
    }
    const v4 = found.find((a: connection.NetAddress) => IPV4.test(a.address));
    const pick = v4 !== undefined ? v4 : found[0];
    if (pick === undefined) {
      throw new Error(`Cannot resolve host name "${h}".`);
    }
    return { address: pick.address, family: IPV4.test(pick.address) ? FAMILY_V4 : FAMILY_V6 };
  }
}
