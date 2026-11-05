import { CommandResult, OutputListener } from '../../core/agent/CommandRunner';
import { AppPaths } from '../../core/common/AppPaths';
import { Strings } from '../../core/common/Strings';
import { PathUtil } from '../../core/fs/PathUtil';
import { CancelToken } from '../../core/llm/CancelToken';
import { ProjectInfo, copyProject } from '../../core/project/ProjectInfo';
import { projectRepository } from '../../core/project/ProjectRepository';
import { ProjectSync, SyncReport } from '../../core/remote/ProjectSync';
import { ConnState, RemoteConnection } from '../../core/remote/RemoteConnection';
import { hostAddress, RemoteHost } from '../../core/remote/RemoteHost';
import { RemoteProjectRunner, SyncListener } from '../../core/remote/RemoteProjectRunner';
import { RemoteShell } from '../../core/remote/RemoteShell';
import { OutputSink, ShellBackend } from '../../core/terminal/ShellBackend';
import { FileManifestStore, SandboxSyncFs } from './SandboxSyncFs';
import { RunTarget } from './RunTarget';
import { SshShellBackend } from './RemoteTerminal';
import { RemoteServices } from './RemoteServices';

/** Saved files are pushed this long after the last save. */
const PUSH_DELAY_MS: number = 1500;

/** What the IDE learns from syncs. */
export interface RemoteTargetHost {
  /** Files the sync changed on the phone ('' = refresh everything). */
  localFilesChanged(paths: string[]): void;
}

/**
 * A phone project that runs on one of the user's computers: owns the connection, the mirror
 * folder there and the two-way sync, and runs commands (agent, Run) on that computer.
 */
@ObservedV2
export class RemoteTarget implements RunTarget, SyncListener {
  readonly host: RemoteHost;
  readonly conn: RemoteConnection;
  @Trace state: string = ConnState.IDLE;
  @Trace error: string = '';
  @Trace syncing: boolean = false;
  @Trace lastSync: number = 0;
  @Trace lastSummary: string = '';
  @Trace conflicts: string[] = [];
  /** Folder on the computer, once known. */
  @Trace remoteDir: string = '';
  private project: ProjectInfo;
  private ideHost: RemoteTargetHost;
  private runner: RemoteProjectRunner | null = null;
  private preparing: Promise<RemoteProjectRunner> | null = null;
  private pushTimer: number = -1;
  private offState: () => void;

  constructor(project: ProjectInfo, host: RemoteHost, ideHost: RemoteTargetHost) {
    this.project = project;
    this.host = host;
    this.ideHost = ideHost;
    this.conn = RemoteServices.connection(host);
    this.remoteDir = project.remoteDir ?? '';
    this.offState = this.conn.onChange((state: string, error: string) => {
      this.state = state;
      this.error = error;
    });
  }

  label(): string {
    return this.host.name + ' (' + hostAddress(this.host) + ')';
  }

  displayName(): string {
    return this.host.name;
  }

  createShell(sink: OutputSink, projectRoot: string): ShellBackend {
    return new SshShellBackend(this.conn, sink, async (): Promise<string> => {
      await this.prepare();
      return this.remoteDirFor(projectRoot);
    });
  }

  /** Connects and settles the mirror folder (default: ~/HarmonyCode/<project> on the computer). */
  prepare(): Promise<RemoteProjectRunner> {
    if (this.runner !== null) {
      return Promise.resolve(this.runner);
    }
    if (this.preparing === null) {
      this.preparing = this.open().finally(() => {
        this.preparing = null;
      });
    }
    return this.preparing as Promise<RemoteProjectRunner>;
  }

  /** Folder on the computer for a project folder on the phone (after prepare). */
  remoteDirFor(localDir: string): string {
    return this.runner !== null ? this.runner.remoteDirFor(localDir) : this.remoteDir;
  }

  async syncNow(): Promise<void> {
    try {
      const r = await this.prepare();
      await r.syncNow(new CancelToken());
    } catch (e) {
      this.error = (e as Error).message;
    }
  }

  /** After a save: push soon, batching quick successive saves. */
  schedulePush(): void {
    if (this.pushTimer >= 0) {
      clearTimeout(this.pushTimer);
    }
    this.pushTimer = setTimeout(() => {
      this.pushTimer = -1;
      if (this.conn.connected) {
        this.syncNow();
      }
    }, PUSH_DELAY_MS);
  }

  dispose(): void {
    if (this.pushTimer >= 0) {
      clearTimeout(this.pushTimer);
    }
    this.offState();
    this.conn.close();
  }

  // ---------- CommandRunner ----------

  describe(): string {
    if (this.runner !== null) {
      return this.runner.describe();
    }
    return `The user's computer ${this.label()} over SSH (connecting). The project is mirrored to a folder there ` +
      'and commands run on that computer; files are synced before and after each command.';
  }

  async run(command: string, cwd: string, timeoutMs: number, cancel: CancelToken,
    onOutput: OutputListener): Promise<CommandResult> {
    const r = await this.prepare();
    return r.run(command, cwd, timeoutMs, cancel, onOutput);
  }

  // ---------- SyncListener ----------

  syncStarted(): void {
    this.syncing = true;
  }

  syncFinished(report: SyncReport | null, error: string): void {
    this.syncing = false;
    if (report === null) {
      this.error = error;
      return;
    }
    this.error = '';
    this.lastSync = Date.now();
    const summary = report.summary();
    this.lastSummary = summary.length > 0 ? summary : Strings.get('remote_sync_up_to_date');
    if (report.conflicts.length > 0) {
      this.conflicts = report.conflicts;
    }
    const changed = report.changedLocally.concat(report.conflicts.map((c: string) => c + '.conflict'));
    if (changed.length > 0) {
      this.ideHost.localFilesChanged(changed.map((rel: string) => PathUtil.join(this.project.path, rel)));
    }
  }

  // ---------- internals ----------

  private async open(): Promise<RemoteProjectRunner> {
    await this.conn.connect();
    let dir = this.remoteDir;
    if (dir.length === 0) {
      const home = this.conn.platform !== null ? this.conn.platform.home : '';
      dir = RemoteProjectRunner.defaultRemoteDir(home, this.project.name);
      this.remember(dir);
    }
    dir = RemoteShell.toSftp(dir);
    this.remoteDir = dir;
    const store = new FileManifestStore(PathUtil.join(AppPaths.sync, this.project.id + '-' + this.host.id + '.json'));
    const sync = new ProjectSync(new SandboxSyncFs(), this.project.path, dir, store);
    const runner = new RemoteProjectRunner(this.conn, sync, this);
    this.runner = runner;
    return runner;
  }

  /** Saves the chosen folder with the project, so later syncs use the same one. */
  private remember(dir: string): void {
    const p = projectRepository.get(this.project.id);
    if (p !== undefined) {
      const c = copyProject(p);
      c.remoteDir = dir;
      projectRepository.update(c);
    }
  }
}
