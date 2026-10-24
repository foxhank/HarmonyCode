import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { Logger, errorMessage } from '../../core/common/Logger';
import { ThemeMode } from '../../core/settings/SettingsStore';

/** Current light/dark state (for web views, which can't read color resources). */
@ObservedV2
export class AppearanceState {
  @Trace isDark: boolean = false;
  private ctx: common.UIAbilityContext | null = null;

  init(ctx: common.UIAbilityContext): void {
    this.ctx = ctx;
    this.isDark = ctx.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  /** Called from EntryAbility.onConfigurationUpdate. */
  onSystemColorMode(mode: ConfigurationConstant.ColorMode | undefined): void {
    this.isDark = mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  /** Applies the user's theme choice; resources then switch between base/ and dark/. */
  applyTheme(theme: string): void {
    const ctx = this.ctx;
    if (ctx === null) {
      return;
    }
    let mode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (theme === ThemeMode.LIGHT) {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else if (theme === ThemeMode.DARK) {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    ctx.getApplicationContext().setColorMode(mode);
  }

  /** Applies the user's language choice ('' = follow system). Takes effect for new UI immediately. */
  applyLanguage(tag: string): void {
    try {
      i18n.System.setAppPreferredLanguage(tag.length > 0 ? tag : 'default');
    } catch (e) {
      Logger.warn('Appearance', errorMessage(e as Error));
    }
  }

  /** 'dark' or 'light' for web views. */
  webTheme(): string {
    return this.isDark ? 'dark' : 'light';
  }
}

export const appearance: AppearanceState = new AppearanceState();
