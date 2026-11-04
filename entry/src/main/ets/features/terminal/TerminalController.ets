import { SettingsStore } from '../../core/settings/SettingsStore';
import { TerminalSession } from '../../core/terminal/TerminalSession';
import { TerminalBridge, TerminalEvents, TerminalJsApi } from './TerminalBridge';

export interface TerminalTheme {
  dark: boolean;
  background: string;
  foreground: string;
  cursor: string;
  selection: string;
}

/**
 * What every terminal view drives: the session (scrollback + backend), the bridge to the
 * xterm.js page, and the Ctrl key of the extra-keys bar. Subclasses choose the backend
 * (project VM / built-in shell, or an SSH shell on a remote computer).
 */
@ObservedV2
export class TerminalController implements TerminalEvents {
  @Trace label: string = '';
  @Trace ctrlArmed: boolean = false;
  readonly session: TerminalSession = new TerminalSession();
  readonly bridge: TerminalBridge = new TerminalBridge();
  /** Object the web page calls into (registered as window.hcTermNative). */
  readonly jsApi: TerminalJsApi;
  protected settings: SettingsStore;
  private themeFn: () => TerminalTheme;

  constructor(settings: SettingsStore, themeFn: () => TerminalTheme) {
    this.settings = settings;
    this.themeFn = themeFn;
    this.jsApi = new TerminalJsApi(this);
  }

  sendKey(seq: string): void {
    this.session.input(seq);
    this.bridge.focus();
  }

  toggleCtrl(): void {
    this.ctrlArmed = !this.ctrlArmed;
    this.bridge.setCtrl(this.ctrlArmed);
  }

  clear(): void {
    this.session.clearScrollback();
    this.bridge.clear();
  }

  applySettings(): void {
    this.bridge.setFontSize(this.settings.terminalFontSize);
  }

  applyTheme(): void {
    const t = this.themeFn();
    this.bridge.setTheme(t.dark, t.background, t.foreground, t.cursor, t.selection);
  }

  // ---------- TerminalEvents ----------

  onTermReady(cols: number, rows: number): void {
    if (!this.bridge.markReady()) {
      return;
    }
    this.applyTheme();
    this.applySettings();
    this.session.attach((data: string) => this.bridge.write(data), cols, rows);
  }

  onTermInput(data: string): void {
    this.session.input(data);
  }

  onTermResize(cols: number, rows: number): void {
    this.session.resize(cols, rows);
  }

  onTermCtrlConsumed(): void {
    this.ctrlArmed = false;
  }

  dispose(): void {
    this.session.dispose();
  }
}
