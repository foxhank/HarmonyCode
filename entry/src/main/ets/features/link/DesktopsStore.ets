import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fromBase64url, LinkAddress, LinkPairing, toBase64url } from '../../core/link/LinkPairing';
import { LinkAuth } from '../../core/link/LinkSession';
import { ConnectedLink } from '../../core/link/LinkPairing';
import { Bytes } from '../../core/remote/ssh/Bytes';
import { Ed25519KeyPair, SocketFactory, SshCrypto } from '../../core/remote/ssh/SshCrypto';
import { SecretStore } from '../../core/settings/SecretStore';

const PREFS_NAME: string = 'link';
const KEY_DESKTOPS: string = 'desktops';
const SECRET_IDENTITY: string = 'harmonycode.link.identity';
const CONNECT_TIMEOUT_MS: number = 6000;

/** A desktop this phone is paired with. */
export interface PairedDesktop {
  id: string;
  name: string;
  /** Last working address first. */
  addresses: LinkAddress[];
  /** The desktop's Ed25519 identity, base64url. */
  serverKey: string;
  os: string;
  pairedAt: number;
  lastConnected: number;
}

/**
 * Desktops paired with HarmonyCode Link, and this phone's own identity key (in the Asset Store).
 * Pairing proves the QR code was seen and pins the desktop's key; later connections resume with
 * both stored keys.
 */
@ObservedV2
export class DesktopsStore {
  @Trace desktops: PairedDesktop[] = [];
  private prefs: preferences.Preferences | null = null;
  private crypto: SshCrypto | null = null;
  private sockets: SocketFactory | null = null;
  private key: Ed25519KeyPair | null = null;

  load(ctx: common.Context, crypto: SshCrypto, sockets: SocketFactory): void {
    this.crypto = crypto;
    this.sockets = sockets;
    const p = preferences.getPreferencesSync(ctx, { name: PREFS_NAME });
    this.prefs = p;
    try {
      this.desktops = JSON.parse(p.getSync(KEY_DESKTOPS, '[]') as string) as PairedDesktop[];
    } catch (e) {
      this.desktops = [];
    }
  }

  get(id: string): PairedDesktop | undefined {
    return this.desktops.find((d: PairedDesktop) => d.id === id);
  }

  remove(id: string): void {
    this.desktops = this.desktops.filter((d: PairedDesktop) => d.id !== id);
    this.save();
  }

  /** Name shown on the desktop's device list. */
  deviceName(): string {
    try {
      const n = deviceInfo.marketName;
      return n.length > 0 ? n : 'HarmonyOS device';
    } catch (e) {
      return 'HarmonyOS device';
    }
  }

  /** Pairs with the desktop that shows `uri`. Throws LinkError explaining what failed. */
  async pair(uri: string): Promise<PairedDesktop> {
    const offer = LinkPairing.parse(uri);
    const auth: LinkAuth = {
      identity: this.identity(), deviceName: this.deviceName(), serverKey: offer.serverKey, pairSecret: offer.secret
    };
    const link = await LinkPairing.connect(this.sockets as SocketFactory, this.crypto as SshCrypto, offer.addresses, auth,
      CONNECT_TIMEOUT_MS);
    const info = link.client.info;
    link.client.close();
    const key = toBase64url(offer.serverKey);
    const existing = this.desktops.find((d: PairedDesktop) => d.serverKey === key);
    const d: PairedDesktop = {
      id: existing !== undefined ? existing.id : 'd' + Date.now().toString(36),
      name: info.name.length > 0 ? info.name : offer.name,
      addresses: DesktopsStore.reorder(offer.addresses, link.address),
      serverKey: key, os: info.os, pairedAt: Date.now(), lastConnected: Date.now()
    };
    this.desktops = this.desktops.filter((x: PairedDesktop) => x.serverKey !== key).concat([d]);
    this.save();
    return d;
  }

  /** Connects to a paired desktop, trying its last working address first. */
  async connect(d: PairedDesktop): Promise<ConnectedLink> {
    const auth: LinkAuth = {
      identity: this.identity(), deviceName: this.deviceName(), serverKey: fromBase64url(d.serverKey),
      pairSecret: new Uint8Array(0)
    };
    const link = await LinkPairing.connect(this.sockets as SocketFactory, this.crypto as SshCrypto, d.addresses, auth,
      CONNECT_TIMEOUT_MS);
    const current = this.get(d.id);
    if (current !== undefined) {
      const updated: PairedDesktop = {
        id: current.id, name: link.client.info.name.length > 0 ? link.client.info.name : current.name,
        addresses: DesktopsStore.reorder(current.addresses, link.address), serverKey: current.serverKey,
        os: link.client.info.os, pairedAt: current.pairedAt, lastConnected: Date.now()
      };
      this.desktops = this.desktops.map((x: PairedDesktop) => x.id === d.id ? updated : x);
      this.save();
    }
    return link;
  }

  /** This phone's identity, created on first use. */
  identity(): Ed25519KeyPair {
    if (this.key !== null) {
      return this.key;
    }
    const stored = SecretStore.get(SECRET_IDENTITY);
    if (stored.length === 128) {
      const raw = Bytes.fromHex(stored);
      this.key = { seed: raw.slice(0, 32), publicKey: raw.slice(32) };
      return this.key;
    }
    const kp = (this.crypto as SshCrypto).ed25519Generate();
    SecretStore.set(SECRET_IDENTITY, Bytes.hex(Bytes.concat([kp.seed, kp.publicKey])));
    this.key = kp;
    return kp;
  }

  private static reorder(list: LinkAddress[], first: LinkAddress): LinkAddress[] {
    return [first].concat(list.filter((a: LinkAddress) => a.host !== first.host || a.port !== first.port));
  }

  private save(): void {
    if (this.prefs !== null) {
      this.prefs.putSync(KEY_DESKTOPS, JSON.stringify(this.desktops));
      this.prefs.flush();
    }
  }
}

export const desktops: DesktopsStore = new DesktopsStore();
