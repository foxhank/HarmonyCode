import { AppConfig } from '../../common/AppConfig';
import { AppPaths } from '../../common/AppPaths';
import { Logger, errorMessage } from '../../common/Logger';
import { Strings } from '../../common/Strings';
import { envImages } from '../../env/EnvImages';
import { FileService } from '../../fs/FileService';
import { PathUtil } from '../../fs/PathUtil';
import { EnvironmentDef, ImageSource } from '../../project/Catalog';
import { OutputSink } from '../ShellBackend';
import { ConsoleWatcher } from './ConsoleWatcher';
import { GuestCommands, GuestProject } from './GuestCommands';
import { VmEngine } from './VmEngine';

const TAG: string = 'VmRuntime';
const PERCENT: number = 100;
const NEWLINE: string = '\r\n';
/** Leading space keeps the IDE's own commands out of bash history. */
const QUIET: string = ' ';

export enum VmPhase {
  /** Nothing started yet in this process. */
  IDLE = 'idle',
  /** Copying the image / firmware before boot. */
  PREPARING = 'preparing',
  /** QEMU is running; waiting for the first shell prompt. */
  BOOTING = 'booting',
  /** Logged in at a shell. */
  READY = 'ready',
  /** QEMU exited. It can't be started again in this process. */
  STOPPED = 'stopped'
}

/** CPU and memory for the VM. */
export interface VmResources {
  cpus: number;
  memoryMb: number;
}

/**
 * The one Linux VM of this app process (QEMU can boot once per process). Terminals attach and
 * detach as projects open and close; the VM keeps running in between. It logs in, prepares the
 * shell, and moves into the attached project's folder.
 */
export class VmRuntime {
  phase: string = VmPhase.IDLE;
  /** Environment of the started VM, '' before start. */
  envId: string = '';
  private engine: VmEngine | null = null;
  private sink: OutputSink | null = null;
  private backlog: string = '';
  private watcher: ConsoleWatcher = new ConsoleWatcher([]);
  private shellPrepared: boolean = false;
  private project: GuestProject | null = null;
  private pendingEnter: boolean = false;
  private queued: string[] = [];

  init(engine: VmEngine): void {
    this.engine = engine;
  }

  isAvailable(): boolean {
    return this.engine !== null && this.engine.isAvailable();
  }

  /** Connects a terminal. Output produced while detached is replayed; the shell moves to `project`. */
  attach(sink: OutputSink, project: GuestProject): void {
    this.sink = sink;
    this.project = project;
    if (this.backlog.length > 0) {
      sink(this.backlog);
      this.backlog = '';
    }
    this.pendingEnter = true;
    if (this.phase === VmPhase.READY && this.watcher.idleAtPrompt()) {
      this.enterProject();
    }
  }

  detach(sink: OutputSink): void {
    if (this.sink === sink) {
      this.sink = null;
    }
  }

  /** Prepares the image if needed and boots `env`. Safe to call once; later calls are ignored. */
  async start(env: EnvironmentDef, resources: VmResources, cols: number, rows: number): Promise<void> {
    if (this.phase !== VmPhase.IDLE || this.engine === null) {
      return;
    }
    const engine = this.engine;
    this.phase = VmPhase.PREPARING;
    this.envId = env.id;
    this.setWindowSize(cols, rows);
    try {
      await envImages.ensureFirmware();
      if (!envImages.isInstalled(env.id)) {
        await this.installBundled(env);
      }
    } catch (e) {
      this.failBeforeBoot(errorMessage(e as Error));
      return;
    }
    const socket = PathUtil.join(AppPaths.temp, AppConfig.VM_SOCKET_NAME);
    if (FileService.exists(socket)) {
      FileService.remove(socket);
    }
    this.watcher = new ConsoleWatcher(env.login);
    this.emit(Strings.get('vm_starting', resources.cpus, resources.memoryMb) + NEWLINE);
    const error = engine.boot({
      kernelPath: envImages.kernelPath(),
      rootfsPath: envImages.rootfsPath(env.id),
      firmwareDir: AppPaths.vmFirmware,
      sharedDir: AppPaths.workspace,
      serialSocket: socket,
      cpus: resources.cpus,
      memoryMb: resources.memoryMb,
      forwardPorts: AppConfig.VM_FORWARDED_PORTS
    }, (text: string) => this.onOutput(text), (code: number) => this.onExit(code));
    if (error.length > 0) {
      this.failBeforeBoot(error);
      return;
    }
    this.phase = VmPhase.BOOTING;
  }

  /** Keystrokes from the terminal. */
  write(data: string): void {
    if (this.engine === null || this.phase === VmPhase.STOPPED) {
      return;
    }
    if (this.engine.write(data)) {
      this.watcher.inputSent();
    }
  }

  /** Runs a command line once the shell is ready (immediately if it already is). */
  run(line: string): void {
    if (this.phase === VmPhase.READY) {
      this.write(line + '\r');
    } else {
      this.queued.push(line);
    }
  }

  /** Publishes the terminal size; the shell applies it before its next prompt (see GuestCommands.init). */
  setWindowSize(cols: number, rows: number): void {
    try {
      FileService.writeText(PathUtil.join(AppPaths.vmControl, AppConfig.VM_WINSIZE_FILE),
        GuestCommands.winsize(cols, rows));
    } catch (e) {
      Logger.warn(TAG, 'winsize: ' + errorMessage(e as Error));
    }
  }

  // ---------- internals ----------

  private async installBundled(env: EnvironmentDef): Promise<void> {
    if (env.image === undefined || env.image.source !== ImageSource.BUNDLED) {
      throw new Error(Strings.get('env_error_no_image'));
    }
    const state = envImages.state(env.id);
    let shown = -1;
    const timer = setInterval(() => {
      const pct = Math.floor(state.progress * PERCENT);
      if (pct !== shown) {
        shown = pct;
        this.emit('\r' + Strings.get('vm_preparing_image', pct + '%'));
      }
    }, AppConfig.VM_PROGRESS_INTERVAL);
    try {
      const ok = await envImages.install(env);
      if (!ok) {
        throw new Error(state.error);
      }
    } finally {
      clearInterval(timer);
      this.emit(NEWLINE);
    }
  }

  private failBeforeBoot(reason: string): void {
    Logger.error(TAG, 'start failed: ' + reason);
    // QEMU never ran, so a later attempt in this process is still possible.
    this.phase = VmPhase.IDLE;
    this.envId = '';
    this.emit(NEWLINE + Strings.get('vm_start_failed', reason) + NEWLINE);
  }

  private onOutput(text: string): void {
    this.emit(text);
    const signal = this.watcher.feed(text);
    if (signal.reply.length > 0) {
      this.write(signal.reply);
      return;
    }
    if (!signal.prompt) {
      return;
    }
    if (!this.shellPrepared) {
      this.shellPrepared = true;
      this.phase = VmPhase.READY;
      this.write(QUIET + GuestCommands.init() + '\r');
      return;
    }
    if (this.pendingEnter) {
      this.enterProject();
      return;
    }
    const next = this.queued.shift();
    if (next !== undefined) {
      this.write(next + '\r');
    }
  }

  private enterProject(): void {
    this.pendingEnter = false;
    if (this.project !== null) {
      this.write(QUIET + GuestCommands.enter(this.project) + '\r');
    }
  }

  private onExit(code: number): void {
    this.phase = VmPhase.STOPPED;
    this.queued = [];
    this.emit(NEWLINE + Strings.get('vm_stopped', code) + NEWLINE);
  }

  private emit(text: string): void {
    if (this.sink !== null) {
      this.sink(text);
      return;
    }
    this.backlog = (this.backlog + text).slice(-AppConfig.VM_BACKLOG_CHARS);
  }
}

export const vmRuntime: VmRuntime = new VmRuntime();
