import { AppConfig } from '../../core/common/AppConfig';
import { EventBus, Events, RenamePayload, Unsubscribe } from '../../core/common/EventBus';
import { Strings } from '../../core/common/Strings';
import { errorMessage } from '../../core/common/Logger';
import { FileService } from '../../core/fs/FileService';
import { PathUtil } from '../../core/fs/PathUtil';
import { SettingsStore } from '../../core/settings/SettingsStore';
import { Buttons } from '../dialogs/Buttons';
import { DialogModel } from '../dialogs/DialogModel';
import { ToastModel } from '../dialogs/ToastModel';
import { EditorBridge, EditorEvents, EditorJsApi } from './EditorBridge';
import { EditorTab } from './EditorTab';

/** What the editor needs from the rest of the workbench. */
export interface EditorHost {
  bus: EventBus;
  dialogs: DialogModel;
  toasts: ToastModel;
  settings: SettingsStore;
  /** A shortcut pressed inside the editor (e.g. 'quickOpen'). */
  runCommand(name: string): void;
  /** A file was opened or activated; bring the editor forward. */
  revealEditor(): void;
  /** CSS background and dark flag for the current theme. */
  editorTheme(): EditorTheme;
}

export interface EditorTheme {
  dark: boolean;
  background: string;
}

const SAVE_CHOICE: number = 1;
const DONT_SAVE_CHOICE: number = 2;

/** Open tabs, the active tab, dirty state and saving. The web view is only a renderer. */
@ObservedV2
export class EditorModel implements EditorEvents {
  @Trace tabs: EditorTab[] = [];
  @Trace activeId: string = '';
  @Trace line: number = 1;
  @Trace col: number = 1;
  readonly bridge: EditorBridge = new EditorBridge();
  /** Object the web page calls into (registered as window.hcNative). */
  readonly jsApi: EditorJsApi;
  private host: EditorHost;
  private autoSaveTimers: Map<string, number> = new Map();
  private subs: Unsubscribe[] = [];

  constructor(host: EditorHost) {
    this.host = host;
    this.jsApi = new EditorJsApi(this);
    this.subs.push(host.bus.on(Events.FILES_CHANGED, () => this.reloadCleanTabs()));
    this.subs.push(host.bus.on(Events.FILE_RENAMED, (p: string) => this.onRenamed(JSON.parse(p) as RenamePayload)));
    this.subs.push(host.bus.on(Events.FILE_DELETED, (p: string) => this.onDeleted(p)));
  }

  get active(): EditorTab | undefined {
    return this.tabs.find((t: EditorTab) => t.id === this.activeId);
  }

  get hasDirty(): boolean {
    return this.tabs.some((t: EditorTab) => t.dirty);
  }

  // ---------- opening ----------

  /** Opens (or focuses) a file; optional 1-based line/column to jump to. */
  openFile(path: string, line: number = 0, col: number = 0): void {
    let tab = this.tabs.find((t: EditorTab) => t.id === path);
    if (tab === undefined) {
      let text = '';
      try {
        text = FileService.readText(path);
      } catch (e) {
        this.host.toasts.error(Strings.get('editor_open_failed', PathUtil.baseName(path), errorMessage(e as Error)));
        return;
      }
      tab = new EditorTab(path, false);
      tab.text = text;
      tab.savedText = text;
      this.tabs.push(tab);
      this.bridge.open(tab.id, text, tab.title, false, true);
    }
    this.activate(tab.id);
    if (line > 0) {
      this.bridge.gotoLine(line, col);
    }
  }

  /** Read-only diff of `original` (HEAD) vs `modified` (working tree). */
  openDiff(path: string, original: string, modified: string): void {
    const id = EditorTab.diffId(path);
    let tab = this.tabs.find((t: EditorTab) => t.id === id);
    if (tab === undefined) {
      tab = new EditorTab(path, true);
      this.tabs.push(tab);
    }
    tab.diffOriginal = original;
    tab.text = modified;
    this.activate(id);
  }

  activate(id: string): void {
    const tab = this.tabs.find((t: EditorTab) => t.id === id);
    if (tab === undefined) {
      return;
    }
    this.activeId = id;
    this.showInView(tab);
    this.host.revealEditor();
  }

  activateRelative(delta: number): void {
    if (this.tabs.length < 2) {
      return;
    }
    const i = this.tabs.findIndex((t: EditorTab) => t.id === this.activeId);
    const next = (i + delta + this.tabs.length) % this.tabs.length;
    this.activate(this.tabs[next].id);
  }

  // ---------- closing ----------

  /** Closes a tab, asking to save if it has changes. Resolves false if the user cancelled. */
  async close(id: string): Promise<boolean> {
    const tab = this.tabs.find((t: EditorTab) => t.id === id);
    if (tab === undefined) {
      return true;
    }
    if (tab.dirty) {
      const choice = await this.host.dialogs.confirm(
        Strings.get('editor_save_changes_title', tab.title), Strings.get('editor_save_changes_message'),
        [Buttons.cancel(), Buttons.save(), Buttons.dontSave()]);
      if (choice === SAVE_CHOICE) {
        if (!this.write(tab, tab.text)) {
          return false;
        }
      } else if (choice !== DONT_SAVE_CHOICE) {
        return false;
      }
    }
    this.remove(tab);
    return true;
  }

  async closeActive(): Promise<void> {
    if (this.activeId.length > 0) {
      await this.close(this.activeId);
    }
  }

  async closeOthers(id: string): Promise<void> {
    for (const t of this.tabs.slice()) {
      if (t.id !== id && !(await this.close(t.id))) {
        return;
      }
    }
  }

  async closeAll(): Promise<boolean> {
    for (const t of this.tabs.slice()) {
      if (!(await this.close(t.id))) {
        return false;
      }
    }
    return true;
  }

  // ---------- saving ----------

  saveActive(): void {
    const tab = this.active;
    if (tab !== undefined && !tab.isDiff) {
      this.bridge.requestSave(tab.id);
      this.write(tab, tab.text); // also save from our copy in case the page is gone
    }
  }

  saveAll(): void {
    for (const t of this.tabs) {
      if (t.dirty) {
        this.write(t, t.text);
      }
    }
  }

  // ---------- settings / theme ----------

  applySettings(): void {
    const s = this.host.settings;
    this.bridge.setOptions(s.fontSize, s.tabSize, s.wordWrap);
  }

  applyTheme(): void {
    const theme = this.host.editorTheme();
    this.bridge.setTheme(theme.dark, theme.background);
  }

  // ---------- EditorEvents (from the web page) ----------

  onEditorReady(): void {
    if (!this.bridge.markReady()) {
      return;
    }
    this.applyTheme();
    this.applySettings();
    for (const t of this.tabs) {
      if (!t.isDiff) {
        this.bridge.open(t.id, t.text, t.title, false, true);
      }
    }
    const active = this.active;
    if (active !== undefined) {
      this.showInView(active);
    }
  }

  onEditorChanged(id: string, text: string): void {
    const tab = this.tabs.find((t: EditorTab) => t.id === id);
    if (tab === undefined || tab.isDiff) {
      return;
    }
    tab.text = text;
    tab.dirty = text !== tab.savedText;
    if (tab.dirty && this.host.settings.autoSave) {
      this.scheduleAutoSave(tab);
    }
  }

  onEditorSave(id: string, text: string): void {
    const tab = this.tabs.find((t: EditorTab) => t.id === id);
    if (tab !== undefined && !tab.isDiff) {
      this.write(tab, text);
    }
  }

  onEditorCursor(line: number, col: number): void {
    this.line = line;
    this.col = col;
  }

  onEditorCommand(name: string): void {
    this.host.runCommand(name);
  }

  dispose(): void {
    this.autoSaveTimers.forEach((t: number) => clearTimeout(t));
    this.autoSaveTimers.clear();
    for (const u of this.subs) {
      u();
    }
    this.subs = [];
  }

  // ---------- internals ----------

  private showInView(tab: EditorTab): void {
    if (tab.isDiff) {
      this.bridge.openDiff(tab.id, tab.diffOriginal, tab.text, tab.title);
    } else {
      this.bridge.show(tab.id);
    }
  }

  private remove(tab: EditorTab): void {
    const i = this.tabs.indexOf(tab);
    this.tabs.splice(i, 1);
    this.bridge.close(tab.id);
    const timer = this.autoSaveTimers.get(tab.id);
    if (timer !== undefined) {
      clearTimeout(timer);
      this.autoSaveTimers.delete(tab.id);
    }
    if (this.activeId === tab.id) {
      const next = this.tabs[Math.min(i, this.tabs.length - 1)];
      this.activeId = next !== undefined ? next.id : '';
      if (next !== undefined) {
        this.showInView(next);
      }
    }
  }

  /** Writes to disk; returns false (and shows an error) on failure. */
  private write(tab: EditorTab, text: string): boolean {
    try {
      FileService.writeText(tab.path, text);
    } catch (e) {
      this.host.toasts.error(Strings.get('editor_save_failed', tab.title, errorMessage(e as Error)));
      return false;
    }
    tab.text = text;
    tab.savedText = text;
    tab.dirty = false;
    this.host.bus.emit(Events.FILE_SAVED, tab.path);
    return true;
  }

  private scheduleAutoSave(tab: EditorTab): void {
    const prev = this.autoSaveTimers.get(tab.id);
    if (prev !== undefined) {
      clearTimeout(prev);
    }
    this.autoSaveTimers.set(tab.id, setTimeout(() => {
      this.autoSaveTimers.delete(tab.id);
      if (tab.dirty && this.tabs.indexOf(tab) >= 0) {
        this.write(tab, tab.text);
      }
    }, AppConfig.AUTO_SAVE_DELAY));
  }

  /** After external changes (terminal, git), refresh tabs without unsaved edits. */
  private reloadCleanTabs(): void {
    for (const t of this.tabs.slice()) {
      if (t.dirty || t.isDiff) {
        continue;
      }
      if (!FileService.exists(t.path)) {
        this.remove(t);
        continue;
      }
      try {
        const text = FileService.readText(t.path);
        if (text !== t.savedText) {
          t.text = text;
          t.savedText = text;
          this.bridge.open(t.id, text, t.title, false, true);
          if (t.id !== this.activeId) {
            const active = this.active;
            if (active !== undefined) {
              this.showInView(active);
            }
          }
        }
      } catch (e) {
        // became unreadable; leave the tab as is
      }
    }
  }

  private onRenamed(p: RenamePayload): void {
    for (const t of this.tabs) {
      if (t.path === p.from || PathUtil.isInside(p.from, t.path)) {
        const oldId = t.id;
        t.retarget(p.to + t.path.substring(p.from.length));
        this.bridge.rename(oldId, t.id, t.title);
        if (this.activeId === oldId) {
          this.activeId = t.id;
        }
      }
    }
  }

  private onDeleted(path: string): void {
    for (const t of this.tabs.slice()) {
      if (PathUtil.isInside(path, t.path)) {
        this.remove(t);
      }
    }
  }
}
