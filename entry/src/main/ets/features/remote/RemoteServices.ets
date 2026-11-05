import { Strings } from '../../core/common/Strings';
import { OhosSockets } from '../../core/remote/platform/OhosSockets';
import { OhosSshCrypto } from '../../core/remote/platform/OhosSshCrypto';
import { HostKeyTrust, RemoteConnection, RemoteEnv } from '../../core/remote/RemoteConnection';
import { hostAddress, RemoteHost } from '../../core/remote/RemoteHost';
import { HostKeyInfo } from '../../core/remote/ssh/SshTransport';
import { ButtonRole, dialogs } from '../dialogs/DialogModel';
import { RemoteHostsStore, remoteHosts } from './RemoteHostsStore';

const KEEPALIVE_MS: number = 20000;
const CONNECT_TIMEOUT_MS: number = 15000;

/**
 * Trusts a host key the user has accepted before; otherwise shows its fingerprint and asks
 * (with a warning when it changed, which can mean someone is intercepting the connection).
 */
class DialogHostKeyTrust implements HostKeyTrust {
  private store: RemoteHostsStore;

  constructor(store: RemoteHostsStore) {
    this.store = store;
  }

  async check(host: RemoteHost, info: HostKeyInfo): Promise<boolean> {
    const value = info.algorithm + ' ' + info.fingerprint;
    const known = this.store.knownHostKey(host);
    if (known === value) {
      return true;
    }
    const changed = known.length > 0;
    const title = changed ? Strings.get('remote_hostkey_changed_title') : Strings.get('remote_hostkey_new_title');
    const message = changed ?
      Strings.get('remote_hostkey_changed_message', hostAddress(host), known, value) :
      Strings.get('remote_hostkey_new_message', hostAddress(host), value);
    const choice = await dialogs.confirm(title, message, [
      { label: $r('app.string.action_cancel'), role: ButtonRole.NORMAL },
      { label: changed ? $r('app.string.remote_hostkey_trust_new') : $r('app.string.remote_hostkey_trust'),
        role: changed ? ButtonRole.DANGER : ButtonRole.PRIMARY }
    ]);
    if (choice !== 1) {
      return false;
    }
    this.store.trustHostKey(host, value);
    return true;
  }
}

/** Platform pieces and per-host connections for remote computers. */
export class RemoteServices {
  static readonly crypto: OhosSshCrypto = new OhosSshCrypto();
  static readonly sockets: OhosSockets = new OhosSockets();
  private static readonly trust: DialogHostKeyTrust = new DialogHostKeyTrust(remoteHosts);

  static env(): RemoteEnv {
    return {
      sockets: RemoteServices.sockets,
      crypto: RemoteServices.crypto,
      secrets: remoteHosts,
      trust: RemoteServices.trust,
      lookup: (id: string) => remoteHosts.get(id),
      keepaliveMs: KEEPALIVE_MS,
      connectTimeoutMs: CONNECT_TIMEOUT_MS
    };
  }

  static connection(host: RemoteHost): RemoteConnection {
    return new RemoteConnection(host, RemoteServices.env());
  }
}
