import { Base64 } from '../remote/ssh/Bytes';
import { ByteStream, SocketFactory, SshCrypto } from '../remote/ssh/SshCrypto';
import { LinkClient } from './LinkClient';
import { DEFAULT_PORT } from './LinkProtocol';
import { LinkAuth, LinkError, LinkSession } from './LinkSession';

const SCHEME: string = 'hclink://pair?';
const KEY_LEN: number = 32;
const SECRET_LEN: number = 16;

/** One address of a desktop. */
export interface LinkAddress {
  host: string;
  port: number;
}

/** What the desktop's QR code (or pairing link) says. */
export interface PairingOffer {
  addresses: LinkAddress[];
  serverKey: Uint8Array;
  secret: Uint8Array;
  name: string;
}

function base64url(s: string): Uint8Array {
  let t = s.replace(new RegExp('-', 'g'), '+').replace(new RegExp('_', 'g'), '/');
  while (t.length % 4 !== 0) {
    t += '=';
  }
  return Base64.decode(t);
}

export function toBase64url(b: Uint8Array): string {
  return Base64.encode(b).replace(new RegExp('\\+', 'g'), '-').replace(new RegExp('/', 'g'), '_')
    .replace(new RegExp('=+$'), '');
}

export function fromBase64url(s: string): Uint8Array {
  return base64url(s);
}

/** Parses "host:port" ("[v6]:port", or a bare host on the default port). */
export function parseAddress(text: string): LinkAddress | null {
  const t = text.trim();
  if (t.length === 0) {
    return null;
  }
  const m = new RegExp('^\\[([^\\]]+)\\](?::(\\d+))?$').exec(t);
  if (m !== null) {
    return { host: m[1], port: m[2] !== undefined ? Number(m[2]) : DEFAULT_PORT };
  }
  const i = t.lastIndexOf(':');
  if (i > 0 && t.indexOf(':') === i) {
    const port = Number(t.substring(i + 1));
    return Number.isInteger(port) && port > 0 && port < 65536 ? { host: t.substring(0, i), port: port } : null;
  }
  return { host: t, port: DEFAULT_PORT };
}

export class LinkPairing {
  /** Parses a pairing link. Throws LinkError explaining what is wrong. */
  static parse(uri: string): PairingOffer {
    const text = uri.trim();
    if (!text.startsWith(SCHEME)) {
      throw new LinkError('This is not a HarmonyCode desktop pairing code.');
    }
    const params: Map<string, string> = new Map();
    for (const part of text.substring(SCHEME.length).split('&')) {
      const eq = part.indexOf('=');
      if (eq > 0) {
        try {
          params.set(part.substring(0, eq), decodeURIComponent(part.substring(eq + 1).replace(new RegExp('\\+', 'g'), ' ')));
        } catch (e) {
          throw new LinkError('The pairing code is damaged.');
        }
      }
    }
    if (params.get('v') !== '1') {
      throw new LinkError('The desktop app uses a different version. Update both apps.');
    }
    const addresses: LinkAddress[] = [];
    for (const a of (params.get('a') ?? '').split(',')) {
      const addr = parseAddress(a);
      if (addr !== null) {
        addresses.push(addr);
      }
    }
    const key = base64url(params.get('k') ?? '');
    const secret = base64url(params.get('s') ?? '');
    if (addresses.length === 0 || key.length !== KEY_LEN || secret.length !== SECRET_LEN) {
      throw new LinkError('The pairing code is incomplete. Show a new code on the desktop.');
    }
    return { addresses: addresses, serverKey: key, secret: secret, name: params.get('n') ?? 'Desktop' };
  }

  /**
   * Connects to the first address that answers and runs the handshake. Address order is kept,
   * so callers put the one that worked last time first.
   */
  static async connect(sockets: SocketFactory, crypto: SshCrypto, addresses: LinkAddress[], auth: LinkAuth,
    timeoutMs: number): Promise<ConnectedLink> {
    const errors: string[] = [];
    for (const a of addresses) {
      let stream: ByteStream;
      try {
        stream = await sockets.connect(a.host, a.port, timeoutMs);
      } catch (e) {
        errors.push(`${a.host}:${a.port}: ${(e as Error).message}`);
        continue;
      }
      // Reaching the port is enough: handshake errors (wrong key, not paired) are final.
      const session = await LinkSession.open(stream, crypto, auth);
      return { client: new LinkClient(session, crypto), address: a };
    }
    throw new LinkError('Cannot reach the desktop. Is the HarmonyCode Desktop app running, and is this device on ' +
      'the same network? (' + errors.join('; ') + ')');
  }
}

export interface ConnectedLink {
  client: LinkClient;
  address: LinkAddress;
}
