import { webview } from '@kit.ArkWeb';
import { Logger, errorMessage } from '../../core/common/Logger';

/** Callbacks from the terminal web page. */
export interface TerminalEvents {
  onTermReady(cols: number, rows: number): void;
  onTermInput(data: string): void;
  onTermResize(cols: number, rows: number): void;
  onTermCtrlConsumed(): void;
}

/** Exposed to the page as `window.hcTermNative` (names must match web/src/terminal.js). */
export class TerminalJsApi {
  private ev: TerminalEvents;

  constructor(ev: TerminalEvents) {
    this.ev = ev;
  }

  ready(cols: number, rows: number): void {
    this.ev.onTermReady(cols, rows);
  }

  input(data: string): void {
    this.ev.onTermInput(data);
  }

  resize(cols: number, rows: number): void {
    this.ev.onTermResize(cols, rows);
  }

  ctrlConsumed(): void {
    this.ev.onTermCtrlConsumed();
  }

  static methods(): string[] {
    return ['ready', 'input', 'resize', 'ctrlConsumed'];
  }
}

export const TERMINAL_JS_NAME: string = 'hcTermNative';

type JsArg = string | number | boolean;

/** Calls into the terminal page; output is batched per frame to limit bridge traffic. */
export class TerminalBridge {
  private ctl: webview.WebviewController | null = null;
  private ready: boolean = false;
  private pending: string = '';
  private flushTimer: number = -1;

  attach(ctl: webview.WebviewController): void {
    this.ctl = ctl;
    this.ready = false;
    this.pending = '';
  }

  detach(ctl: webview.WebviewController): void {
    if (this.ctl === ctl) {
      this.ctl = null;
      this.ready = false;
    }
  }

  markReady(): boolean {
    if (this.ready || this.ctl === null) {
      return false;
    }
    this.ready = true;
    return true;
  }

  write(data: string): void {
    this.pending += data;
    if (this.flushTimer < 0) {
      this.flushTimer = setTimeout(() => {
        this.flushTimer = -1;
        const chunk = this.pending;
        this.pending = '';
        this.call('write', [chunk]);
      }, 0);
    }
  }

  focus(): void {
    this.call('focus', []);
  }

  clear(): void {
    this.call('clear', []);
  }

  setFontSize(size: number): void {
    this.call('setFontSize', [size]);
  }

  setCtrl(on: boolean): void {
    this.call('setCtrl', [on]);
  }

  setTheme(dark: boolean, background: string, foreground: string, cursor: string, selection: string): void {
    this.call('setTheme', [dark, background, foreground, cursor, selection]);
  }

  private call(fn: string, args: JsArg[]): void {
    const ctl = this.ctl;
    if (!this.ready || ctl === null) {
      return;
    }
    const js = 'window.hcTerm && hcTerm.' + fn + '(' + args.map((a: JsArg) => JSON.stringify(a)).join(',') + ')';
    try {
      ctl.runJavaScript(js).catch((e: Error) => Logger.warn('TerminalBridge', fn + ': ' + errorMessage(e)));
    } catch (e) {
      Logger.warn('TerminalBridge', fn + ': ' + errorMessage(e as Error));
    }
  }
}
