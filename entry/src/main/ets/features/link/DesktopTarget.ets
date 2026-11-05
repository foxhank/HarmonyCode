import { CommandResult, OutputListener } from '../../core/agent/CommandRunner';
import { AppPaths } from '../../core/common/AppPaths';
import { Strings } from '../../core/common/Strings';
import { PathUtil } from '../../core/fs/PathUtil';
import { CancelToken } from '../../core/llm/CancelToken';
import { LinkClient } from '../../core/link/LinkClient';
import { LinkEntry } from '../../core/link/LinkProtocol';
import { LinkProvider, LinkRunner } from '../../core/link/LinkRunner';
import { DesktopInfo, linkFailure } from '../../core/link/LinkSession';
import { LinkSync } from '../../core/link/LinkSync';
import { ProjectInfo } from '../../core/project/ProjectInfo';
import { SyncReport } from '../../core/remote/ProjectSync';
import { SyncListener } from '../../core/remote/RemoteProjectRunner';
import { OutputSink, ShellBackend } from '../../core/terminal/ShellBackend';
import { RemoteServices } from '../remote/RemoteServices';
import { RemoteTargetHost } from '../remote/RemoteTarget';
import { RunTarget, TargetState } from '../remote/RunTarget';
import { FileManifestStore, SandboxSyncFs } from '../remote/SandboxSyncFs';
import { DesktopShellBackend } from './DesktopShell';
import { desktops, PairedDesktop } from './DesktopsStore';

/** Local changes are pushed this soon after they happen. */
const PUSH_DELAY_MS: number = 300;
/** Desktop changes are pulled this soon after they are announced (batches bursts). */
const PULL_DELAY_MS: number = 150;
/** Full re-listing as a safety net. */
const FULL_SYNC_MS: number = 30000;
const RETRY_MIN_MS: number = 2000;
const RETRY_MAX_MS: number = 30000;

/**
 * A phone project that runs on the paired desktop over HarmonyCode Link. Keeps a live, encrypted
 * connection while the project is open: desktop changes arrive as events and are pulled at once,
 * phone changes are pushed within a moment, commands run on the desktop.
 */
@ObservedV2
export class DesktopTarget implements RunTarget, LinkProvider, SyncListener {
  readonly desktop: PairedDesktop;
  @Trace state: string = TargetState.IDLE;
  @Trace error: string = '';
  @Trace syncing: boolean = false;
  @Trace lastSync: number = 0;
  @Trace lastSummary: string = '';
  @Trace conflicts: string[] = [];
  @Trace remoteDir: string = '';
  private project: ProjectInfo;
  private ideHost: RemoteTargetHost;
  private sync: LinkSync;
  private runner: LinkRunner;
  private live: LinkClient | null = null;
  private connecting: Promise<LinkClient> | null = null;
  private pushTimer: number = -1;
  private pullTimer: number = -1;
  private retryTimer: number = -1;
  private fullTimer: number = -1;
  private retryMs: number = RETRY_MIN_MS;
  private disposed: boolean = false;
  private desktopInfo: DesktopInfo | null = null;

  constructor(project: ProjectInfo, desktop: PairedDesktop, ideHost: RemoteTargetHost) {
    this.project = project;
    this.desktop = desktop;
    this.ideHost = ideHost;
    const folder = (project.remoteDir ?? '').length > 0 ? project.remoteDir as string : DesktopTarget.folderFor(project);
    this.remoteDir = desktop.name + ': ' + folder;
    const store = new FileManifestStore(PathUtil.join(AppPaths.sync, project.id + '-desktop-' + desktop.id + '.json'));
    this.sync = new LinkSync(new SandboxSyncFs(), project.path, folder, RemoteServices.crypto, store);
    this.runner = new LinkRunner(this, this.sync, this);
    this.fullTimer = setInterval(() => {
      if (this.live !== null && !this.live.isClosed) {
        this.syncWith(this.live, true);
      }
    }, FULL_SYNC_MS);
    // Open the link right away so changes flow both ways while the project is open.
    this.client().catch(() => {
    });
  }

  /** The project's folder in the desktop's workspace. */
  static folderFor(p: ProjectInfo): string {
    const safe = p.name.replace(new RegExp('[^A-Za-z0-9._ -]+', 'g'), '-').trim();
    return safe.length > 0 ? safe : 'project';
  }

  displayName(): string {
    return this.desktop.name;
  }

  label(): string {
    return this.desktop.name + ' (HarmonyCode Desktop)';
  }

  // ---------- LinkProvider ----------

  client(): Promise<LinkClient> {
    if (this.live !== null && !this.live.isClosed) {
      return Promise.resolve(this.live);
    }
    if (this.disposed) {
      return Promise.reject(linkFailure('The project was closed.'));
    }
    if (this.connecting === null) {
      this.connecting = this.open().finally(() => {
        this.connecting = null;
      });
    }
    return this.connecting as Promise<LinkClient>;
  }

  info(): DesktopInfo | null {
    return this.desktopInfo;
  }

  // ---------- RunTarget ----------

  describe(): string {
    return this.runner.describe();
  }

  run(command: string, cwd: string, timeoutMs: number, cancel: CancelToken,
    onOutput: OutputListener): Promise<CommandResult> {
    return this.runner.run(command, cwd, timeoutMs, cancel, onOutput);
  }

  async syncNow(): Promise<void> {
    try {
      await this.syncWith(await this.client(), true);
    } catch (e) {
      this.error = (e as Error).message;
    }
  }

  schedulePush(): void {
    if (this.pushTimer >= 0) {
      clearTimeout(this.pushTimer);
    }
    this.pushTimer = setTimeout(() => {
      this.pushTimer = -1;
      if (this.live !== null && !this.live.isClosed) {
        this.syncWith(this.live, false);
      }
    }, PUSH_DELAY_MS);
  }

  createShell(sink: OutputSink, projectRoot: string): ShellBackend {
    return new DesktopShellBackend(this, sink, projectRoot, this.desktop.name);
  }

  dispose(): void {
    this.disposed = true;
    for (const t of [this.pushTimer, this.pullTimer, this.retryTimer]) {
      if (t >= 0) {
        clearTimeout(t);
      }
    }
    clearInterval(this.fullTimer);
    this.live?.close();
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
    const s = report.summary();
    this.lastSummary = s.length > 0 ? s : Strings.get('remote_sync_up_to_date');
    if (report.conflicts.length > 0) {
      this.conflicts = report.conflicts;
    }
    const changed = report.changedLocally.concat(report.conflicts.map((c: string) => c + '.conflict'));
    if (changed.length > 0) {
      this.ideHost.localFilesChanged(changed.map((rel: string) => PathUtil.join(this.project.path, rel)));
    }
  }

  // ---------- internals ----------

  private async open(): Promise<LinkClient> {
    this.state = TargetState.CONNECTING;
    try {
      const link = await desktops.connect(this.desktop);
      const c = link.client;
      this.live = c;
      this.desktopInfo = c.info;
      this.state = TargetState.CONNECTED;
      this.error = '';
      this.retryMs = RETRY_MIN_MS;
      c.onChanged((entries: LinkEntry[]) => this.onDesktopChanged(entries));
      c.session.onClose((e: string) => this.onLost(c, e));
      this.syncWith(c, true);
      return c;
    } catch (e) {
      this.state = TargetState.FAILED;
      this.error = (e as Error).message;
      this.scheduleRetry();
      throw e as Error;
    }
  }

  private onDesktopChanged(entries: LinkEntry[]): void {
    if (!this.sync.applyEvent(entries)) {
      return;
    }
    if (this.pullTimer >= 0) {
      clearTimeout(this.pullTimer);
    }
    this.pullTimer = setTimeout(() => {
      this.pullTimer = -1;
      if (this.live !== null && !this.live.isClosed) {
        this.syncWith(this.live, false);
      }
    }, PULL_DELAY_MS);
  }

  private onLost(c: LinkClient, error: string): void {
    if (this.live !== c) {
      return;
    }
    this.live = null;
    if (this.disposed) {
      return;
    }
    this.state = TargetState.FAILED;
    this.error = error.length > 0 ? error : Strings.get('remote_term_lost');
    this.scheduleRetry();
  }

  /** Reconnects in the background with backoff while the project is open. */
  private scheduleRetry(): void {
    if (this.disposed || this.retryTimer >= 0) {
      return;
    }
    this.retryTimer = setTimeout(() => {
      this.retryTimer = -1;
      this.client().catch(() => {
      });
    }, this.retryMs);
    this.retryMs = Math.min(RETRY_MAX_MS, this.retryMs * 2);
  }

  private async syncWith(c: LinkClient, refresh: boolean): Promise<void> {
    this.syncStarted();
    try {
      const report = await this.sync.sync(c, refresh);
      this.syncFinished(report, '');
    } catch (e) {
      this.syncFinished(null, (e as Error).message);
    }
  }
}
