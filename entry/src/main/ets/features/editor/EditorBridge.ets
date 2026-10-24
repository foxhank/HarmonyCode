import { webview } from '@kit.ArkWeb';
import { Logger, errorMessage } from '../../core/common/Logger';

/** Callbacks from the editor web page. */
export interface EditorEvents {
  onEditorReady(): void;
  onEditorChanged(id: string, text: string): void;
  onEditorSave(id: string, text: string): void;
  onEditorCursor(line: number, col: number): void;
  onEditorCommand(name: string): void;
}

/** Object exposed to the page as `window.hcNative` (method names must match web/src/editor.js). */
export class EditorJsApi {
  private ev: EditorEvents;

  constructor(ev: EditorEvents) {
    this.ev = ev;
  }

  ready(): void {
    this.ev.onEditorReady();
  }

  changed(id: string, text: string): void {
    this.ev.onEditorChanged(id, text);
  }

  save(id: string, text: string): void {
    this.ev.onEditorSave(id, text);
  }

  cursor(line: number, col: number): void {
    this.ev.onEditorCursor(line, col);
  }

  command(name: string): void {
    this.ev.onEditorCommand(name);
  }

  static methods(): string[] {
    return ['ready', 'changed', 'save', 'cursor', 'command'];
  }
}

export const EDITOR_JS_NAME: string = 'hcNative';

type JsArg = string | number | boolean;

/** Calls into the editor page (`window.hc`). Calls made before the page is ready are dropped. */
export class EditorBridge {
  private ctl: webview.WebviewController | null = null;
  private ready: boolean = false;

  attach(ctl: webview.WebviewController): void {
    this.ctl = ctl;
    this.ready = false;
  }

  detach(ctl: webview.WebviewController): void {
    if (this.ctl === ctl) {
      this.ctl = null;
      this.ready = false;
    }
  }

  /** Returns true the first time the attached page reports ready. */
  markReady(): boolean {
    if (this.ready || this.ctl === null) {
      return false;
    }
    this.ready = true;
    return true;
  }

  open(id: string, text: string, name: string, readOnly: boolean, force: boolean): void {
    this.call('open', [id, text, name, readOnly, force]);
  }

  show(id: string): void {
    this.call('show', [id]);
  }

  close(id: string): void {
    this.call('close', [id]);
  }

  rename(oldId: string, newId: string, name: string): void {
    this.call('rename', [oldId, newId, name]);
  }

  requestSave(id: string): void {
    this.call('requestSave', [id]);
  }

  requestSaveAll(): void {
    this.call('requestSaveAll', []);
  }

  gotoLine(line: number, col: number): void {
    this.call('gotoLine', [line, col]);
  }

  focus(): void {
    this.call('focus', []);
  }

  setOptions(fontSize: number, tabSize: number, wrap: boolean): void {
    this.call('setOptions', [fontSize, tabSize, wrap]);
  }

  setTheme(dark: boolean, background: string): void {
    this.call('setTheme', [dark, background]);
  }

  openDiff(id: string, original: string, modified: string, name: string): void {
    this.call('openDiff', [id, original, modified, name]);
  }

  private call(fn: string, args: JsArg[]): void {
    const ctl = this.ctl;
    if (!this.ready || ctl === null) {
      return;
    }
    const js = 'window.hc && hc.' + fn + '(' + args.map((a: JsArg) => JSON.stringify(a)).join(',') + ')';
    try {
      ctl.runJavaScript(js).catch((e: Error) => Logger.warn('EditorBridge', fn + ': ' + errorMessage(e)));
    } catch (e) {
      Logger.warn('EditorBridge', fn + ': ' + errorMessage(e as Error));
    }
  }
}
