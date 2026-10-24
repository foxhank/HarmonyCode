import { AppConfig } from '../../core/common/AppConfig';
import { EventBus, Events, Unsubscribe } from '../../core/common/EventBus';
import { Strings } from '../../core/common/Strings';
import { errorMessage, Logger } from '../../core/common/Logger';
import { FileService } from '../../core/fs/FileService';
import { PathUtil } from '../../core/fs/PathUtil';
import { GitClient } from '../../core/git/GitClient';
import { ChangeCode, GitBranchList, GitChange, GitCommit } from '../../core/git/GitTypes';
import { Buttons } from '../dialogs/Buttons';
import { DialogModel } from '../dialogs/DialogModel';
import { ToastModel } from '../dialogs/ToastModel';

/** Long-running operations, shown in the status bar while busy. */
export class ScmOp {
  static readonly NONE: string = '';
  static readonly REFRESH: string = 'refresh';
  static readonly COMMIT: string = 'commit';
  static readonly PULL: string = 'pull';
  static readonly PUSH: string = 'push';
  static readonly FETCH: string = 'fetch';
  static readonly CHECKOUT: string = 'checkout';
  static readonly INIT: string = 'init';
}

export interface ScmHost {
  bus: EventBus;
  dialogs: DialogModel;
  toasts: ToastModel;
  openFile(path: string): void;
  openDiff(path: string, original: string, modified: string): void;
  /** New status, e.g. for explorer decorations. */
  statusChanged(changes: GitChange[]): void;
}

/** Name of the default remote. */
export const ORIGIN: string = 'origin';
const PERCENT: number = 100;

/** Source Control for one repository: changes, staging, commit, branches, sync. */
@ObservedV2
export class ScmModel {
  @Trace isRepo: boolean = false;
  @Trace loaded: boolean = false;
  @Trace branch: string = '';
  @Trace staged: GitChange[] = [];
  @Trace unstaged: GitChange[] = [];
  @Trace commits: GitCommit[] = [];
  @Trace branches: GitBranchList = { current: '', local: [], remote: [] };
  @Trace remoteUrl: string = '';
  @Trace message: string = '';
  @Trace busy: string = ScmOp.NONE;
  @Trace progress: string = '';
  readonly root: string;
  private git: GitClient;
  private host: ScmHost;
  private timer: number = -1;
  private subs: Unsubscribe[] = [];

  constructor(root: string, git: GitClient, host: ScmHost) {
    this.root = root;
    this.git = git;
    this.host = host;
    const later = (): void => this.refreshSoon();
    this.subs.push(host.bus.on(Events.FILE_SAVED, later));
    this.subs.push(host.bus.on(Events.FILES_CHANGED, later));
    this.subs.push(host.bus.on(Events.FILE_RENAMED, later));
    this.subs.push(host.bus.on(Events.FILE_DELETED, later));
    this.subs.push(host.bus.on(Events.GIT_CHANGED, later));
    this.refresh();
  }

  get changeCount(): number {
    return this.staged.length + this.unstaged.length;
  }

  // ---------- reading ----------

  refreshSoon(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
    }
    this.timer = setTimeout(() => {
      this.timer = -1;
      this.refresh();
    }, AppConfig.GIT_REFRESH_DEBOUNCE);
  }

  async refresh(): Promise<void> {
    try {
      this.isRepo = await this.git.isRepo(this.root);
      if (!this.isRepo) {
        this.clearState();
        return;
      }
      const changes = await this.git.status(this.root);
      this.staged = changes.filter((c: GitChange) => c.staged);
      this.unstaged = changes.filter((c: GitChange) => !c.staged);
      this.branches = await this.git.branches(this.root);
      this.branch = this.branches.current;
      this.commits = await this.git.log(this.root, AppConfig.GIT_LOG_DEPTH);
      const remotes = await this.git.remotes(this.root);
      const origin = remotes.find((r) => r.remote === ORIGIN);
      this.remoteUrl = origin !== undefined ? origin.url : '';
      this.host.statusChanged(changes);
    } catch (e) {
      Logger.warn('Scm', errorMessage(e as Error));
    } finally {
      this.loaded = true;
    }
  }

  /** Opens HEAD vs working tree (or the file itself when it's new/deleted). */
  async openChange(c: GitChange): Promise<void> {
    const abs = PathUtil.join(this.root, c.path);
    if (c.code === ChangeCode.UNTRACKED || c.code === ChangeCode.ADDED) {
      this.host.openFile(abs);
      return;
    }
    try {
      const original = await this.git.readHead(this.root, c.path);
      const modified = FileService.exists(abs) ? FileService.readText(abs) : '';
      this.host.openDiff(abs, original, modified);
    } catch (e) {
      this.host.toasts.error(errorMessage(e as Error));
    }
  }

  // ---------- staging ----------

  async stage(c: GitChange): Promise<void> {
    await this.guard(ScmOp.NONE, () => this.git.stage(this.root, c.path));
  }

  async unstage(c: GitChange): Promise<void> {
    await this.guard(ScmOp.NONE, () => this.git.unstage(this.root, c.path));
  }

  async stageAll(): Promise<void> {
    await this.guard(ScmOp.NONE, () => this.git.stageAll(this.root));
  }

  async unstageAll(): Promise<void> {
    await this.guard(ScmOp.NONE, async () => {
      for (const c of this.staged) {
        await this.git.unstage(this.root, c.path);
      }
    });
  }

  async discard(c: GitChange): Promise<void> {
    const name = PathUtil.baseName(c.path);
    const choice = await this.host.dialogs.confirm(Strings.get('scm_discard_title', name),
      Strings.get(c.code === ChangeCode.UNTRACKED ? 'scm_discard_untracked_message' : 'scm_discard_message', name),
      [Buttons.cancel(), Buttons.discard()]);
    if (choice === 1) {
      await this.guard(ScmOp.NONE, () => this.git.discard(this.root, c.path));
      this.host.bus.emit(Events.FILES_CHANGED, PathUtil.join(this.root, c.path));
    }
  }

  // ---------- commit & sync ----------

  async commit(): Promise<void> {
    const msg = this.message.trim();
    if (msg.length === 0) {
      this.host.toasts.error(Strings.get('scm_commit_need_message'));
      return;
    }
    if (this.staged.length === 0 && this.unstaged.length === 0) {
      this.host.toasts.info(Strings.get('scm_nothing_to_commit'));
      return;
    }
    const ok = await this.guard(ScmOp.COMMIT, async () => {
      if (this.staged.length === 0) {
        await this.git.stageAll(this.root); // like VS Code's "commit all" when nothing is staged
      }
      await this.git.commit(this.root, msg);
    });
    if (ok) {
      this.message = '';
      this.host.toasts.info(Strings.get('scm_committed'));
    }
  }

  async pull(): Promise<void> {
    if (await this.guard(ScmOp.PULL, () => this.git.pull(this.root, this.progressFn()))) {
      this.host.bus.emit(Events.FILES_CHANGED, '');
      this.host.toasts.info(Strings.get('scm_pulled'));
    }
  }

  async push(): Promise<void> {
    if (this.remoteUrl.length === 0) {
      await this.setRemote();
      if (this.remoteUrl.length === 0) {
        return;
      }
    }
    if (await this.guard(ScmOp.PUSH, () => this.git.push(this.root, this.progressFn()))) {
      this.host.toasts.info(Strings.get('scm_pushed'));
    }
  }

  async fetch(): Promise<void> {
    await this.guard(ScmOp.FETCH, () => this.git.fetch(this.root, this.progressFn()));
  }

  async init(): Promise<void> {
    await this.guard(ScmOp.INIT, () => this.git.init(this.root));
  }

  // ---------- branches & remotes ----------

  async checkout(branch: string): Promise<void> {
    if (branch === this.branch) {
      return;
    }
    if (await this.guard(ScmOp.CHECKOUT, () => this.git.checkout(this.root, branch))) {
      this.host.bus.emit(Events.FILES_CHANGED, '');
    }
  }

  async createBranch(): Promise<void> {
    const name = await this.host.dialogs.prompt($r('app.string.scm_new_branch'),
      $r('app.string.scm_branch_placeholder'), '', Buttons.create(), Buttons.cancel(),
      (v: string) => ScmModel.isValidBranch(v) ? '' : Strings.get('scm_invalid_branch'));
    if (name !== null) {
      await this.guard(ScmOp.CHECKOUT, () => this.git.createBranch(this.root, name, true));
    }
  }

  async setRemote(): Promise<void> {
    const url = await this.host.dialogs.prompt($r('app.string.scm_set_remote'),
      $r('app.string.clone_url_placeholder'), this.remoteUrl, Buttons.ok(), Buttons.cancel(),
      (v: string) => v.startsWith('http') ? '' : Strings.get('clone_error_url'));
    if (url !== null) {
      await this.guard(ScmOp.NONE, () => this.git.setRemote(this.root, ORIGIN, url));
    }
  }

  dispose(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
    }
    for (const u of this.subs) {
      u();
    }
    this.subs = [];
  }

  // ---------- internals ----------

  static isValidBranch(name: string): boolean {
    return name.length > 0 && new RegExp('^[A-Za-z0-9._/-]+$').test(name) && !name.startsWith('-') &&
      name.indexOf('..') < 0 && !name.endsWith('/') && !name.endsWith('.lock');
  }

  private clearState(): void {
    this.staged = [];
    this.unstaged = [];
    this.commits = [];
    this.branch = '';
    this.remoteUrl = '';
    this.host.statusChanged([]);
  }

  private progressFn(): (phase: string, loaded: number, total: number) => void {
    return (phase: string, loaded: number, total: number): void => {
      this.progress = total > 0 ? phase + ' ' + Math.floor(loaded * PERCENT / total) + '%' : phase;
    };
  }

  /** Runs an operation with busy state, error toast and refresh. Returns success. */
  private async guard(op: string, fn: () => Promise<void>): Promise<boolean> {
    if (this.busy !== ScmOp.NONE && op !== ScmOp.NONE) {
      return false;
    }
    this.busy = op;
    this.progress = '';
    try {
      await fn();
      return true;
    } catch (e) {
      this.host.toasts.error(Strings.get('git_error', errorMessage(e as Error)));
      return false;
    } finally {
      this.busy = ScmOp.NONE;
      this.progress = '';
      await this.refresh();
    }
  }
}
