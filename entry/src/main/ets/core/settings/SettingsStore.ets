import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppConfig } from '../common/AppConfig';
import { SecretStore } from './SecretStore';

export enum ThemeMode {
  SYSTEM = 'system',
  LIGHT = 'light',
  DARK = 'dark'
}

/** '' follows the system language; otherwise a BCP-47 tag such as 'en' or 'zh-Hans'. */
export type LanguageTag = string;

/** User preferences. Observable so views update when they change. */
@ObservedV2
export class SettingsStore {
  @Trace fontSize: number = AppConfig.EDITOR_FONT_DEFAULT;
  @Trace tabSize: number = AppConfig.TAB_SIZE_DEFAULT;
  @Trace wordWrap: boolean = false;
  @Trace autoSave: boolean = true;
  @Trace terminalFontSize: number = AppConfig.TERMINAL_FONT_DEFAULT;
  @Trace theme: string = ThemeMode.SYSTEM;
  @Trace language: LanguageTag = '';
  @Trace gitName: string = '';
  @Trace gitEmail: string = '';
  @Trace gitUsername: string = '';
  @Trace hasGitToken: boolean = false;
  private prefs: preferences.Preferences | null = null;

  load(ctx: common.Context): void {
    const p = preferences.getPreferencesSync(ctx, { name: AppConfig.PREFS_SETTINGS });
    this.prefs = p;
    this.fontSize = p.getSync('fontSize', this.fontSize) as number;
    this.tabSize = p.getSync('tabSize', this.tabSize) as number;
    this.wordWrap = p.getSync('wordWrap', this.wordWrap) as boolean;
    this.autoSave = p.getSync('autoSave', this.autoSave) as boolean;
    this.terminalFontSize = p.getSync('terminalFontSize', this.terminalFontSize) as number;
    this.theme = p.getSync('theme', this.theme) as string;
    this.language = p.getSync('language', this.language) as string;
    this.gitName = p.getSync('gitName', '') as string;
    this.gitEmail = p.getSync('gitEmail', '') as string;
    this.gitUsername = p.getSync('gitUsername', '') as string;
    this.hasGitToken = SecretStore.get(AppConfig.SECRET_GIT_TOKEN).length > 0;
  }

  save(): void {
    const p = this.prefs;
    if (p === null) {
      return;
    }
    p.putSync('fontSize', this.fontSize);
    p.putSync('tabSize', this.tabSize);
    p.putSync('wordWrap', this.wordWrap);
    p.putSync('autoSave', this.autoSave);
    p.putSync('terminalFontSize', this.terminalFontSize);
    p.putSync('theme', this.theme);
    p.putSync('language', this.language);
    p.putSync('gitName', this.gitName);
    p.putSync('gitEmail', this.gitEmail);
    p.putSync('gitUsername', this.gitUsername);
    p.flush();
  }

  gitToken(): string {
    return SecretStore.get(AppConfig.SECRET_GIT_TOKEN);
  }

  setGitToken(token: string): void {
    SecretStore.set(AppConfig.SECRET_GIT_TOKEN, token);
    this.hasGitToken = token.length > 0;
  }

  authorName(): string {
    return this.gitName.length > 0 ? this.gitName : AppConfig.GIT_FALLBACK_NAME;
  }

  authorEmail(): string {
    return this.gitEmail.length > 0 ? this.gitEmail : AppConfig.GIT_FALLBACK_EMAIL;
  }
}

export const settingsStore: SettingsStore = new SettingsStore();
