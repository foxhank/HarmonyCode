import { pasteboard } from '@kit.BasicServicesKit';
import { EventBus, Events, RenamePayload, Unsubscribe } from '../../core/common/EventBus';
import { Strings } from '../../core/common/Strings';
import { errorMessage } from '../../core/common/Logger';
import { FileService } from '../../core/fs/FileService';
import { PathUtil } from '../../core/fs/PathUtil';
import { ChangeCode, GitChange } from '../../core/git/GitTypes';
import { Buttons } from '../dialogs/Buttons';
import { DialogModel } from '../dialogs/DialogModel';
import { ToastModel } from '../dialogs/ToastModel';

/** One visible line of the file tree. */
export interface TreeRow {
  path: string;
  name: string;
  isDir: boolean;
  depth: number;
  expanded: boolean;
  /** Git change code ('' when unchanged). Folders get MODIFIED when anything inside changed. */
  git: string;
}

export interface ExplorerHost {
  bus: EventBus;
  dialogs: DialogModel;
  toasts: ToastModel;
  openFile(path: string): void;
}

/** File tree for one project root. */
@ObservedV2
export class ExplorerModel {
  @Trace rows: TreeRow[] = [];
  @Trace selected: string = '';
  readonly root: string;
  private host: ExplorerHost;
  private expanded: Set<string> = new Set<string>();
  private decorations: Map<string, string> = new Map<string, string>();
  private subs: Unsubscribe[] = [];

  constructor(root: string, host: ExplorerHost) {
    this.root = root;
    this.host = host;
    const refresh = (): void => this.refresh();
    this.subs.push(host.bus.on(Events.FILES_CHANGED, refresh));
    this.subs.push(host.bus.on(Events.FILE_DELETED, refresh));
    this.subs.push(host.bus.on(Events.FILE_RENAMED, refresh));
    this.refresh();
  }

  refresh(): void {
    const out: TreeRow[] = [];
    this.collect(this.root, 0, out);
    this.rows = out;
  }

  /** Click on a row: folders toggle, files open. */
  activate(row: TreeRow): void {
    this.selected = row.path;
    if (row.isDir) {
      if (this.expanded.has(row.path)) {
        this.expanded.delete(row.path);
      } else {
        this.expanded.add(row.path);
      }
      this.refresh();
    } else {
      this.host.openFile(row.path);
    }
  }

  collapseAll(): void {
    this.expanded.clear();
    this.refresh();
  }

  /** Expands parents of `path` and selects it. */
  reveal(path: string): void {
    let dir = PathUtil.dirName(path);
    while (PathUtil.isInside(this.root, dir) && dir !== this.root) {
      this.expanded.add(dir);
      dir = PathUtil.dirName(dir);
    }
    this.selected = path;
    this.refresh();
  }

  /** Git status decorations (from Source Control). */
  setDecorations(changes: GitChange[]): void {
    const map = new Map<string, string>();
    for (const c of changes) {
      const abs = PathUtil.join(this.root, c.path);
      if (!map.has(abs) || !c.staged) {
        map.set(abs, c.code);
      }
      let dir = PathUtil.dirName(abs);
      while (PathUtil.isInside(this.root, dir) && dir !== this.root) {
        map.set(dir, ChangeCode.MODIFIED);
        dir = PathUtil.dirName(dir);
      }
    }
    this.decorations = map;
    this.refresh();
  }

  /** Folder a "new file" action should target, based on the selection. */
  targetDir(path?: string): string {
    const p = path ?? this.selected;
    if (p.length === 0) {
      return this.root;
    }
    return FileService.isDir(p) ? p : PathUtil.dirName(p);
  }

  async newFile(dir?: string): Promise<void> {
    const parent = this.targetDir(dir);
    const name = await this.host.dialogs.prompt($r('app.string.explorer_new_file'),
      $r('app.string.explorer_name_placeholder'), '', Buttons.create(), Buttons.cancel(),
      (v: string) => this.validateNew(parent, v));
    if (name === null) {
      return;
    }
    const path = PathUtil.join(parent, name);
    if (!this.run(() => FileService.createFile(path))) {
      return;
    }
    this.expanded.add(parent);
    this.host.bus.emit(Events.FILES_CHANGED, path);
    this.host.openFile(path);
    this.reveal(path);
  }

  async newFolder(dir?: string): Promise<void> {
    const parent = this.targetDir(dir);
    const name = await this.host.dialogs.prompt($r('app.string.explorer_new_folder'),
      $r('app.string.explorer_name_placeholder'), '', Buttons.create(), Buttons.cancel(),
      (v: string) => this.validateNew(parent, v));
    if (name === null) {
      return;
    }
    const path = PathUtil.join(parent, name);
    if (!this.run(() => FileService.createDir(path))) {
      return;
    }
    this.expanded.add(parent);
    this.expanded.add(path);
    this.host.bus.emit(Events.FILES_CHANGED, path);
    this.reveal(path);
  }

  async rename(path: string): Promise<void> {
    const parent = PathUtil.dirName(path);
    const current = PathUtil.baseName(path);
    const name = await this.host.dialogs.prompt($r('app.string.explorer_rename'),
      $r('app.string.explorer_name_placeholder'), current, Buttons.rename(), Buttons.cancel(),
      (v: string) => v === current ? '' : this.validateNew(parent, v));
    if (name === null || name === current) {
      return;
    }
    const to = PathUtil.join(parent, name);
    if (this.run(() => FileService.rename(path, to))) {
      if (this.expanded.has(path)) {
        this.expanded.delete(path);
        this.expanded.add(to);
      }
      const payload: RenamePayload = { from: path, to: to };
      this.host.bus.emit(Events.FILE_RENAMED, JSON.stringify(payload));
      this.selected = to;
    }
  }

  async remove(path: string): Promise<void> {
    const name = PathUtil.baseName(path);
    const key = FileService.isDir(path) ? 'explorer_delete_folder_message' : 'explorer_delete_file_message';
    const choice = await this.host.dialogs.confirm(Strings.get('explorer_delete_title', name), Strings.get(key, name),
      [Buttons.cancel(), Buttons.del()]);
    if (choice !== 1) {
      return;
    }
    if (this.run(() => FileService.remove(path))) {
      this.expanded.delete(path);
      this.host.bus.emit(Events.FILE_DELETED, path);
    }
  }

  copyPath(path: string, relative: boolean): void {
    const text = relative ? PathUtil.relative(this.root, path) : path;
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.host.toasts.info(Strings.get('explorer_path_copied'));
    }).catch((e: Error) => this.host.toasts.error(errorMessage(e)));
  }

  dispose(): void {
    for (const u of this.subs) {
      u();
    }
    this.subs = [];
  }

  private collect(dir: string, depth: number, out: TreeRow[]): void {
    for (const e of FileService.list(dir)) {
      const expanded = e.isDir && this.expanded.has(e.path);
      out.push({
        path: e.path, name: e.name, isDir: e.isDir, depth: depth, expanded: expanded,
        git: this.decorations.get(e.path) ?? ''
      });
      if (expanded) {
        this.collect(e.path, depth + 1, out);
      }
    }
  }

  private validateNew(parent: string, name: string): string {
    if (!PathUtil.isValidName(name)) {
      return Strings.get('explorer_invalid_name');
    }
    if (FileService.exists(PathUtil.join(parent, name))) {
      return Strings.get('err_already_exists', name);
    }
    return '';
  }

  /** Runs a file operation; shows errors as a toast. */
  private run(op: () => void): boolean {
    try {
      op();
      return true;
    } catch (e) {
      this.host.toasts.error(errorMessage(e as Error));
      return false;
    }
  }
}
