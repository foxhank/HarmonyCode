import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger, errorMessage } from '../../core/common/Logger';
import { RemoteSecrets } from '../../core/remote/RemoteConnection';
import { AuthMethod, RemoteHost, SSH_DEFAULT_PORT } from '../../core/remote/RemoteHost';
import { SshCrypto } from '../../core/remote/ssh/SshCrypto';
import { SshKeys, UserKey } from '../../core/remote/ssh/SshKeys';
import { SecretStore } from '../../core/settings/SecretStore';

const TAG: string = 'RemoteHosts';
const PREFS_NAME: string = 'remote';
const KEY_HOSTS: string = 'hosts';
const KEY_KNOWN: string = 'knownHosts';
const SECRET_PASSWORD: string = 'harmonycode.remote.password.';
const SECRET_KEY: string = 'harmonycode.remote.userkey';
const KEY_COMMENT: string = 'harmonycode';

/**
 * The user's saved computers. Host details live in preferences; passwords and the app's private
 * key in the encrypted Asset Store; trusted host keys ("known hosts") in preferences.
 */
@ObservedV2
export class RemoteHostsStore implements RemoteSecrets {
  @Trace hosts: RemoteHost[] = [];
  /** "ssh-ed25519 AAAA... harmonycode" or '' when no key exists yet. */
  @Trace publicKey: string = '';
  private prefs: preferences.Preferences | null = null;
  private known: Record<string, string> = {};
  private key: UserKey | null = null;
  private crypto: SshCrypto | null = null;

  load(ctx: common.Context, crypto: SshCrypto): void {
    this.crypto = crypto;
    const p = preferences.getPreferencesSync(ctx, { name: PREFS_NAME });
    this.prefs = p;
    try {
      this.hosts = JSON.parse(p.getSync(KEY_HOSTS, '[]') as string) as RemoteHost[];
    } catch (e) {
      this.hosts = [];
    }
    try {
      this.known = JSON.parse(p.getSync(KEY_KNOWN, '{}') as string) as Record<string, string>;
    } catch (e) {
      this.known = {};
    }
    const pem = SecretStore.get(SECRET_KEY);
    if (pem.length > 0) {
      try {
        this.key = SshKeys.fromOpenSsh(pem);
        this.publicKey = SshKeys.publicKeyLine(this.key);
      } catch (e) {
        Logger.error(TAG, 'stored key unreadable: ' + errorMessage(e as Error));
      }
    }
  }

  // ---------- hosts ----------

  get(id: string): RemoteHost | undefined {
    return this.hosts.find((h: RemoteHost) => h.id === id);
  }

  /** Hosts most recently used first. */
  sorted(): RemoteHost[] {
    return this.hosts.slice().sort((a: RemoteHost, b: RemoteHost) => b.lastUsed - a.lastUsed);
  }

  blank(): RemoteHost {
    return {
      id: '', name: '', host: '', port: SSH_DEFAULT_PORT, username: '', auth: AuthMethod.KEY, jumpHostId: '',
      startDir: '', lastUsed: 0
    };
  }

  /** Adds (empty id) or replaces a host. Returns the stored host. */
  upsert(h: RemoteHost): RemoteHost {
    const copy: RemoteHost = {
      id: h.id.length > 0 ? h.id : 'h' + Date.now().toString(36), name: h.name.trim(), host: h.host.trim(),
      port: h.port, username: h.username.trim(), auth: h.auth, jumpHostId: h.jumpHostId, startDir: h.startDir.trim(),
      lastUsed: h.lastUsed
    };
    if (copy.name.length === 0) {
      copy.name = copy.host;
    }
    const others = this.hosts.filter((x: RemoteHost) => x.id !== copy.id);
    this.hosts = others.concat([copy]);
    this.save();
    return copy;
  }

  remove(id: string): void {
    SecretStore.remove(SECRET_PASSWORD + id);
    // Hosts that tunneled through it now connect directly.
    this.hosts = this.hosts.filter((x: RemoteHost) => x.id !== id).map((x: RemoteHost): RemoteHost => {
      if (x.jumpHostId !== id) {
        return x;
      }
      return {
        id: x.id, name: x.name, host: x.host, port: x.port, username: x.username, auth: x.auth, jumpHostId: '',
        startDir: x.startDir, lastUsed: x.lastUsed
      };
    });
    this.save();
  }

  touch(id: string): void {
    const h = this.get(id);
    if (h !== undefined) {
      h.lastUsed = Date.now();
      this.upsert(h);
    }
  }

  // ---------- secrets ----------

  password(hostId: string): string {
    return SecretStore.get(SECRET_PASSWORD + hostId);
  }

  hasPassword(hostId: string): boolean {
    return hostId.length > 0 && this.password(hostId).length > 0;
  }

  setPassword(hostId: string, password: string): void {
    SecretStore.set(SECRET_PASSWORD + hostId, password);
  }

  userKey(): UserKey | null {
    return this.key;
  }

  /** Creates the app's Ed25519 key (replacing any existing one). */
  generateKey(): void {
    if (this.crypto === null) {
      return;
    }
    this.storeKey(SshKeys.generate(this.crypto, KEY_COMMENT));
  }

  /** Uses a pasted OpenSSH private key. Throws SshKeyError explaining what is wrong. */
  importKey(text: string): void {
    this.storeKey(SshKeys.fromOpenSsh(text));
  }

  private storeKey(key: UserKey): void {
    if (this.crypto === null) {
      return;
    }
    SecretStore.set(SECRET_KEY, SshKeys.toOpenSsh(this.crypto, key));
    this.key = key;
    this.publicKey = SshKeys.publicKeyLine(key);
  }

  // ---------- known hosts ----------

  knownHostKey(h: RemoteHost): string {
    const v = this.known[RemoteHostsStore.knownId(h)];
    return v !== undefined ? v : '';
  }

  trustHostKey(h: RemoteHost, value: string): void {
    this.known[RemoteHostsStore.knownId(h)] = value;
    this.save();
  }

  forgetHostKey(h: RemoteHost): void {
    const next: Record<string, string> = {};
    const id = RemoteHostsStore.knownId(h);
    for (const k of Object.keys(this.known)) {
      if (k !== id) {
        next[k] = this.known[k];
      }
    }
    this.known = next;
    this.save();
  }

  private static knownId(h: RemoteHost): string {
    return h.host.toLowerCase() + ':' + h.port;
  }

  private save(): void {
    const p = this.prefs;
    if (p === null) {
      return;
    }
    p.putSync(KEY_HOSTS, JSON.stringify(this.hosts));
    p.putSync(KEY_KNOWN, JSON.stringify(this.known));
    p.flush();
  }
}

export const remoteHosts: RemoteHostsStore = new RemoteHostsStore();
