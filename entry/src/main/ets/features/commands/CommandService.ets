import { Strings } from '../../core/common/Strings';

/** Same shortcut twice within this window counts as one press (ms). */
const SHORTCUT_REPEAT_MS: number = 120;

/** Command ids. Shortcut names sent by the editor page (web/src/editor.js) use the same ids. */
export class CommandId {
  static readonly QUICK_OPEN: string = 'quickOpen';
  static readonly PALETTE: string = 'palette';
  static readonly SAVE: string = 'save';
  static readonly SAVE_ALL: string = 'saveAll';
  static readonly CLOSE_TAB: string = 'closeTab';
  static readonly NEXT_TAB: string = 'nextTab';
  static readonly PREV_TAB: string = 'prevTab';
  static readonly TOGGLE_SIDEBAR: string = 'toggleSidebar';
  static readonly TOGGLE_TERMINAL: string = 'toggleTerminal';
  static readonly EXPLORER: string = 'explorer';
  static readonly SEARCH: string = 'search';
  static readonly GIT: string = 'git';
  static readonly RUN: string = 'run';
  static readonly NEW_FILE: string = 'newFile';
  static readonly NEW_FOLDER: string = 'newFolder';
  static readonly GIT_COMMIT: string = 'gitCommit';
  static readonly GIT_PULL: string = 'gitPull';
  static readonly GIT_PUSH: string = 'gitPush';
  static readonly GIT_BRANCH: string = 'gitBranch';
  static readonly SETTINGS: string = 'settings';
  static readonly CLOSE_PROJECT: string = 'closeProject';
}

export interface WorkbenchCommand {
  id: string;
  /** String resource name for the title shown in the palette. */
  titleKey: string;
  /** Shortcut hint, e.g. 'Ctrl+P' ('' if none). */
  keys: string;
  run: () => void;
}

/** Registry of workbench commands (palette, shortcuts, editor key bindings). */
export class CommandService {
  private list: WorkbenchCommand[] = [];

  register(cmds: WorkbenchCommand[]): void {
    for (const c of cmds) {
      this.list = this.list.filter((x: WorkbenchCommand) => x.id !== c.id);
      this.list.push(c);
    }
  }

  all(): WorkbenchCommand[] {
    return this.list.slice();
  }

  title(c: WorkbenchCommand): string {
    return Strings.get(c.titleKey);
  }

  /** Runs a command; returns false if the id is unknown. */
  run(id: string): boolean {
    const c = this.list.find((x: WorkbenchCommand) => x.id === id);
    if (c === undefined) {
      return false;
    }
    c.run();
    return true;
  }

  /** The command bound to a shortcut such as 'Ctrl+P' ('' if none). */
  idForKeys(keys: string): string {
    if (keys.length === 0) {
      return '';
    }
    const c = this.list.find((x: WorkbenchCommand) => x.keys === keys);
    return c === undefined ? '' : c.id;
  }

  /**
   * Runs a command triggered by a shortcut. The editor page and the native key handler can
   * both see the same key press, so a repeat of the same id within a short window is ignored.
   */
  runShortcut(id: string): boolean {
    const now = Date.now();
    if (id === this.lastShortcut && now - this.lastShortcutAt < SHORTCUT_REPEAT_MS) {
      return true;
    }
    this.lastShortcut = id;
    this.lastShortcutAt = now;
    return this.run(id);
  }

  private lastShortcut: string = '';
  private lastShortcutAt: number = 0;
}
