import { AgentFs, FsEntry } from '../../core/agent/AgentFs';
import { Strings } from '../../core/common/Strings';
import { PathUtil } from '../../core/fs/PathUtil';
import { ButtonRole, DialogModel } from '../dialogs/DialogModel';
import { ToastModel } from '../dialogs/ToastModel';

/** A file open in the remote text editor. */
@ObservedV2
export class RemoteDoc {
  readonly path: string;
  @Trace text: string;
  @Trace saving: boolean = false;
  private saved: string;

  constructor(path: string, text: string) {
    this.path = path;
    this.text = text;
    this.saved = text;
  }

  get dirty(): boolean {
    return this.text !== this.saved;
  }

  markSaved(): void {
    this.saved = this.text;
  }
}

/** Browses and edits files on the remote computer over SFTP. */
@ObservedV2
export class RemoteFilesModel {
  @Trace dir: string = '';
  @Trace entries: FsEntry[] = [];
  @Trace loading: boolean = false;
  @Trace error: string = '';
  @Trace doc: RemoteDoc | null = null;
  private fs: AgentFs;
  private dialogs: DialogModel;
  private toasts: ToastModel;
  private seq: number = 0;

  constructor(fs: AgentFs, dialogs: DialogModel, toasts: ToastModel) {
    this.fs = fs;
    this.dialogs = dialogs;
    this.toasts = toasts;
  }

  /** Path segments of the current folder, for the breadcrumb. */
  crumbs(): string[] {
    return this.dir.split('/').filter((s: string) => s.length > 0);
  }

  crumbPath(index: number): string {
    return '/' + this.crumbs().slice(0, index + 1).join('/');
  }

  async open(dir: string): Promise<void> {
    const seq = ++this.seq;
    this.loading = true;
    this.error = '';
    try {
      const list = await this.fs.list(dir);
      if (seq !== this.seq) {
        return;
      }
      this.dir = dir;
      this.entries = list;
    } catch (e) {
      if (seq === this.seq) {
        this.error = (e as Error).message;
      }
    } finally {
      if (seq === this.seq) {
        this.loading = false;
      }
    }
  }

  refresh(): void {
    if (this.dir.length > 0) {
      this.open(this.dir);
    }
  }

  up(): void {
    if (this.dir !== '/' && this.dir.length > 0) {
      this.open(PathUtil.dirName(this.dir));
    }
  }

  tap(e: FsEntry): void {
    if (e.isDir) {
      this.open(e.path);
    } else {
      this.openFile(e.path);
    }
  }

  async openFile(path: string): Promise<void> {
    try {
      this.doc = new RemoteDoc(path, await this.fs.readText(path));
    } catch (e) {
      this.toasts.error((e as Error).message);
    }
  }

  async save(): Promise<void> {
    const d = this.doc;
    if (d === null || d.saving) {
      return;
    }
    d.saving = true;
    try {
      await this.fs.writeText(d.path, d.text);
      d.markSaved();
      this.toasts.info(Strings.get('remote_files_saved', PathUtil.baseName(d.path)));
      if (PathUtil.dirName(d.path) === this.dir) {
        this.refresh();
      }
    } catch (e) {
      this.toasts.error((e as Error).message);
    } finally {
      d.saving = false;
    }
  }

  async closeDoc(): Promise<void> {
    const d = this.doc;
    if (d !== null && d.dirty) {
      const choice = await this.dialogs.confirm(Strings.get('remote_files_unsaved_title'),
        Strings.get('remote_files_unsaved_message', PathUtil.baseName(d.path)), [
          { label: $r('app.string.action_cancel'), role: ButtonRole.NORMAL },
          { label: $r('app.string.remote_files_discard'), role: ButtonRole.DANGER },
          { label: $r('app.string.action_save'), role: ButtonRole.PRIMARY }
        ]);
      if (choice === 2) {
        await this.save();
        if (d.dirty) {
          return;
        }
      } else if (choice !== 1) {
        return;
      }
    }
    this.doc = null;
  }

  async create(folder: boolean): Promise<void> {
    const name = await this.dialogs.prompt(folder ? $r('app.string.remote_files_new_folder') :
      $r('app.string.remote_files_new_file'), $r('app.string.remote_files_name_placeholder'), '',
      { label: $r('app.string.action_create'), role: ButtonRole.PRIMARY },
      { label: $r('app.string.action_cancel'), role: ButtonRole.NORMAL },
      (v: string) => PathUtil.isValidName(v) ? '' : Strings.get('explorer_invalid_name'));
    if (name === null) {
      return;
    }
    const path = PathUtil.join(this.dir, name);
    try {
      if (await this.fs.stat(path) !== null) {
        this.toasts.error(Strings.get('err_already_exists', name));
        return;
      }
      if (folder) {
        await this.fs.mkdirs(path);
      } else {
        await this.fs.writeText(path, '');
      }
      this.refresh();
      if (!folder) {
        this.openFile(path);
      }
    } catch (e) {
      this.toasts.error((e as Error).message);
    }
  }

  async remove(e: FsEntry): Promise<void> {
    const choice = await this.dialogs.confirm(Strings.get('remote_files_delete_title'),
      Strings.get(e.isDir ? 'remote_files_delete_folder' : 'remote_files_delete_file', e.name), [
        { label: $r('app.string.action_cancel'), role: ButtonRole.NORMAL },
        { label: $r('app.string.action_delete'), role: ButtonRole.DANGER }
      ]);
    if (choice !== 1) {
      return;
    }
    try {
      await this.fs.remove(e.path);
      this.refresh();
    } catch (err) {
      this.toasts.error((err as Error).message);
    }
  }
}
