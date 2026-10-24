import { resourceManager } from '@kit.LocalizationKit';
import { common } from '@kit.AbilityKit';

const BYTE: number = 0xff;
const OPAQUE: number = 0xff;
const HEX: number = 16;
const HEX_DIGITS: number = 2;

/** Converts color resources to CSS so web views match the current (light/dark) app theme. */
export class ColorUtil {
  private static mgr: resourceManager.ResourceManager | null = null;

  static init(ctx: common.Context): void {
    ColorUtil.mgr = ctx.resourceManager;
  }

  /** CSS color for a color resource in the current color mode. */
  static css(res: Resource): string {
    const mgr = ColorUtil.mgr;
    if (mgr === null) {
      return '';
    }
    const argb = mgr.getColorSync(res.id);
    const a = (argb >>> 24) & BYTE;
    const r = (argb >>> 16) & BYTE;
    const g = (argb >>> 8) & BYTE;
    const b = argb & BYTE;
    if (a === OPAQUE) {
      return '#' + ColorUtil.hex(r) + ColorUtil.hex(g) + ColorUtil.hex(b);
    }
    return 'rgba(' + r + ',' + g + ',' + b + ',' + (a / OPAQUE).toFixed(3) + ')';
  }

  private static hex(n: number): string {
    return n.toString(HEX).padStart(HEX_DIGITS, '0');
  }
}
