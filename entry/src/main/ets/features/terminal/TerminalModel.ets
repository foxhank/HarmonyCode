import { formatBytes } from '../../core/common/ByteFormat';
import { Strings } from '../../core/common/Strings';
import { GitClient } from '../../core/git/GitClient';
import { envImages, ImageStatus, Unsubscribe } from '../../core/env/EnvImages';
import { Catalog, EnvironmentDef, ImageSource } from '../../core/project/Catalog';
import { ProjectInfo } from '../../core/project/ProjectInfo';
import { SettingsStore } from '../../core/settings/SettingsStore';
import { ShellBackend, ShellHost } from '../../core/terminal/ShellBackend';
import { BuiltinShell } from '../../core/terminal/builtin/BuiltinShell';
import { GuestCommands } from '../../core/terminal/vm/GuestCommands';
import { VmPhase, vmRuntime } from '../../core/terminal/vm/VmRuntime';
import { VmShell } from '../../core/terminal/vm/VmShell';
import { CatalogText } from '../app/CatalogText';
import { RunTarget } from '../remote/RunTarget';
import { TerminalController, TerminalTheme } from './TerminalController';

const RUN_BUILTIN: string = 'run';

/** The integrated terminal of a project: the hiSH VM when available, else the built-in shell. */
@ObservedV2
export class TerminalModel extends TerminalController {
  @Trace usingVm: boolean = false;
  private project: ProjectInfo;
  private git: GitClient;
  private host: ShellHost;
  private unsubscribeImages: Unsubscribe;
  /** Set when the project runs on one of the user's computers. */
  private remote: RunTarget | null;

  constructor(project: ProjectInfo, git: GitClient, host: ShellHost, settings: SettingsStore,
    themeFn: () => TerminalTheme, remote: RunTarget | null = null) {
    super(settings, themeFn);
    this.project = project;
    this.git = git;
    this.host = host;
    this.remote = remote;
    this.session.setBackend(this.createBackend());
    this.label = this.session.label();
    this.unsubscribeImages = envImages.onChange((envId: string) => this.onImageChanged(envId));
  }

  get runsRemotely(): boolean {
    return this.remote !== null;
  }

  /** Runs the project's run command. */
  run(): void {
    const remote = this.remote;
    if (remote !== null) {
      // Push the latest edits first, then run in the computer's shell.
      remote.syncNow().then(() => {
        if (this.project.runCommand.length > 0) {
          this.session.runLine(this.project.runCommand);
        }
      });
      return;
    }
    if (this.usingVm && this.project.runCommand.length > 0) {
      this.session.runLine(this.project.runCommand);
    } else {
      this.session.runLine(RUN_BUILTIN);
    }
  }

  dispose(): void {
    this.unsubscribeImages();
    super.dispose();
  }

  // ---------- internals ----------

  /** Switches from the built-in shell to the VM once this project's environment finishes installing. */
  private onImageChanged(envId: string): void {
    const env = Catalog.environment(this.project.envId);
    if (this.remote !== null || this.usingVm || env === undefined || envId !== env.id || !envImages.isInstalled(envId) ||
      this.vmBlocker(env).length > 0) {
      return;
    }
    this.session.setBackend(this.createBackend());
    this.label = this.session.label();
  }

  private createBackend(): ShellBackend {
    const remote = this.remote;
    if (remote !== null) {
      return remote.createShell(this.session.output, this.project.path);
    }
    const env = Catalog.environment(this.project.envId);
    if (env === undefined || !env.isVm) {
      return this.builtin(Strings.get('terminal_banner_no_runtime'));
    }
    const blocker = this.vmBlocker(env);
    if (blocker.length > 0) {
      return this.builtin(blocker);
    }
    this.usingVm = true;
    return new VmShell(env, GuestCommands.project(this.project, env),
      { cpus: this.settings.vmCpus, memoryMb: this.settings.vmMemoryMb },
      this.session.output, CatalogText.envName(env.id));
  }

  /** Why this project's VM can't be used right now ('' when it can). */
  private vmBlocker(env: EnvironmentDef): string {
    const name = CatalogText.envName(env.id);
    if (!vmRuntime.isAvailable()) {
      return Strings.get('terminal_banner_vm_unavailable', name);
    }
    if (vmRuntime.phase === VmPhase.STOPPED) {
      return Strings.get('terminal_banner_vm_stopped', CatalogText.envName(vmRuntime.envId));
    }
    if (vmRuntime.envId.length > 0 && vmRuntime.envId !== env.id) {
      return Strings.get('terminal_banner_vm_busy', CatalogText.envName(vmRuntime.envId), name);
    }
    const bundled = env.image !== undefined && env.image.source === ImageSource.BUNDLED;
    if (bundled || envImages.isInstalled(env.id)) {
      return '';
    }
    if (envImages.state(env.id).status !== ImageStatus.MISSING) {
      return Strings.get('terminal_banner_vm_downloading', name);
    }
    return Strings.get('terminal_banner_vm_not_installed', name, formatBytes(envImages.installBytes(env)));
  }

  private builtin(banner: string): BuiltinShell {
    this.usingVm = false;
    return new BuiltinShell(this.session.output, this.host, this.git, banner);
  }
}
