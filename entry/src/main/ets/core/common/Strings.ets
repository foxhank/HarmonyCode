import { resourceManager } from '@kit.LocalizationKit';
import { common } from '@kit.AbilityKit';
import { Logger } from './Logger';

/**
 * Localized text for code that isn't a UI attribute (shell output, toasts, errors).
 * UI components should use $r('app.string.x') directly; this is for everything else.
 * Keys are the names in resources/<locale>/element/string.json and plural.json.
 */
export class Strings {
  private static mgr: resourceManager.ResourceManager | null = null;

  static init(ctx: common.Context): void {
    Strings.mgr = ctx.resourceManager;
  }

  /** Looks up a string by name; %s / %d placeholders are filled from args. */
  static get(name: string, ...args: (string | number)[]): string {
    const mgr = Strings.mgr;
    if (mgr === null) {
      return name;
    }
    try {
      return args.length > 0 ? mgr.getStringByNameSync(name, ...args) : mgr.getStringByNameSync(name);
    } catch (e) {
      Logger.warn('Strings', 'missing string: ' + name);
      return name;
    }
  }

  /** Plural-aware lookup (resources/<locale>/element/plural.json); %d is filled with count. */
  static plural(name: string, count: number): string {
    const mgr = Strings.mgr;
    if (mgr === null) {
      return name;
    }
    try {
      return mgr.getPluralStringByNameSync(name, count);
    } catch (e) {
      Logger.warn('Strings', 'missing plural: ' + name);
      return name;
    }
  }
}
