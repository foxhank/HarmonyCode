import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { Logger, errorMessage } from '../common/Logger';

/** Secrets (tokens) in the system Asset Store — encrypted, never in plain preferences. */
export class SecretStore {
  static get(alias: string): string {
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, SecretStore.encode(alias));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const res: asset.AssetMap[] = asset.querySync(query);
      if (res.length === 0) {
        return '';
      }
      return SecretStore.decode(res[0].get(asset.Tag.SECRET) as Uint8Array);
    } catch (e) {
      return ''; // not found
    }
  }

  /** Stores (or clears, with '') a secret. */
  static set(alias: string, value: string): void {
    SecretStore.remove(alias);
    if (value.length === 0) {
      return;
    }
    try {
      const attr: asset.AssetMap = new Map();
      attr.set(asset.Tag.ALIAS, SecretStore.encode(alias));
      attr.set(asset.Tag.SECRET, SecretStore.encode(value));
      attr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
      asset.addSync(attr);
    } catch (e) {
      Logger.error('SecretStore', errorMessage(e as Error));
      throw e as Error;
    }
  }

  static remove(alias: string): void {
    try {
      const q: asset.AssetMap = new Map();
      q.set(asset.Tag.ALIAS, SecretStore.encode(alias));
      asset.removeSync(q);
    } catch (e) {
      // nothing stored
    }
  }

  private static encode(s: string): Uint8Array {
    return new util.TextEncoder().encodeInto(s);
  }

  private static decode(b: Uint8Array): string {
    return util.TextDecoder.create('utf-8').decodeToString(b);
  }
}
