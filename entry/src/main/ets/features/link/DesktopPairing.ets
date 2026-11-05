import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { Strings } from '../../core/common/Strings';
import { ButtonRole, dialogs } from '../dialogs/DialogModel';
import { toasts } from '../dialogs/ToastModel';
import { desktops, PairedDesktop } from './DesktopsStore';

/** Scan-canceled code of ScanKit (the user closed the scanner). */
const SCAN_CANCELED: number = 1000500002;

/** The two ways to pair: scan the desktop's QR code, or paste its pairing link. */
export class DesktopPairing {
  static async scan(ctx: common.Context): Promise<PairedDesktop | null> {
    let text = '';
    try {
      const r = await scanBarcode.startScanForResult(ctx, {
        scanTypes: [scanCore.ScanType.QR_CODE], enableMultiMode: false, enableAlbum: true
      });
      text = r.originalValue;
    } catch (e) {
      const err = e as BusinessError;
      if (err.code !== SCAN_CANCELED) {
        toasts.error(Strings.get('link_scan_failed', err.message ?? String(err.code)));
      }
      return null;
    }
    return DesktopPairing.pair(text);
  }

  static async paste(): Promise<PairedDesktop | null> {
    const text = await dialogs.prompt($r('app.string.link_paste_title'), $r('app.string.link_paste_placeholder'), '',
      { label: $r('app.string.link_pair'), role: ButtonRole.PRIMARY },
      { label: $r('app.string.action_cancel'), role: ButtonRole.NORMAL });
    return text === null || text.length === 0 ? null : DesktopPairing.pair(text);
  }

  private static async pair(uri: string): Promise<PairedDesktop | null> {
    toasts.info(Strings.get('link_pairing'));
    try {
      const d = await desktops.pair(uri);
      toasts.info(Strings.get('link_paired', d.name));
      return d;
    } catch (e) {
      toasts.error((e as Error).message);
      return null;
    }
  }

  static async forget(d: PairedDesktop): Promise<void> {
    const choice = await dialogs.confirm(Strings.get('link_forget_title'), Strings.get('link_forget_message', d.name), [
      { label: $r('app.string.action_cancel'), role: ButtonRole.NORMAL },
      { label: $r('app.string.link_forget'), role: ButtonRole.DANGER }
    ]);
    if (choice === 1) {
      desktops.remove(d.id);
    }
  }
}
