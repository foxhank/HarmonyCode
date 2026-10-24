import { Strings } from '../../core/common/Strings';
import { GitClient } from '../../core/git/GitClient';
import { Catalog } from '../../core/project/Catalog';
import { ProjectInfo } from '../../core/project/ProjectInfo';
import { SettingsStore } from '../../core/settings/SettingsStore';
import { ShellHost } from '../../core/terminal/ShellBackend';
import { TerminalSession } from '../../core/terminal/TerminalSession';
import { BuiltinShell } from '../../core/terminal/builtin/BuiltinShell';
import { VmManager, VmState } from '../../core/terminal/vm/VmManager';
import { VmShell } from '../../core/terminal/vm/VmShell';
import { CatalogText } from '../app/CatalogText';
import { TerminalBridge, TerminalEvents, TerminalJsApi } from './TerminalBridge';

const RUN_BUILTIN: string = 'run';

export interface TerminalTheme {
  dark: boolean;
  background: string;
  foreground: string;
  cursor: string;
  selection: string;
}

/** The integrated terminal: picks the hiSH VM when available, else the built-in shell. */
@ObservedV2
export class TerminalModel implements TerminalEvents {
  @Trace label: string = '';
  @Trace usingVm: boolean = false;
  @Trace ctrlArmed: boolean = false;
  readonly session: TerminalSession = new TerminalSession();
  readonly bridge: TerminalBridge = new TerminalBridge();
  /** Object the web page calls into (registered as window.hcTermNative). */
  readonly jsApi: TerminalJsApi;
  private project: ProjectInfo;
  private settings: SettingsStore;
  private themeFn: () => TerminalTheme;

  constructor(project: ProjectInfo, git: GitClient, host: ShellHost, settings: SettingsStore,
    themeFn: () => TerminalTheme) {
    this.project = project;
    this.settings = settings;
    this.themeFn = themeFn;
    this.jsApi = new TerminalJsApi(this);
    this.session.setBackend(this.createBackend(git, host));
    this.label = this.session.label();
  }

  /** Runs the project's run command. */
  run(): void {
    if (this.usingVm && this.project.runCommand.length > 0) {
      this.session.runLine(this.project.runCommand);
    } else {
      this.session.runLine(RUN_BUILTIN);
    }
  }

  sendKey(seq: string): void {
    this.session.input(seq);
    this.bridge.focus();
  }

  toggleCtrl(): void {
    this.ctrlArmed = !this.ctrlArmed;
    this.bridge.setCtrl(this.ctrlArmed);
  }

  clear(): void {
    this.session.clearScrollback();
    this.bridge.clear();
  }

  applySettings(): void {
    this.bridge.setFontSize(this.settings.terminalFontSize);
  }

  applyTheme(): void {
    const t = this.themeFn();
    this.bridge.setTheme(t.dark, t.background, t.foreground, t.cursor, t.selection);
  }

  // ---------- TerminalEvents ----------

  onTermReady(cols: number, rows: number): void {
    if (!this.bridge.markReady()) {
      return;
    }
    this.applyTheme();
    this.applySettings();
    this.session.attach((data: string) => this.bridge.write(data), cols, rows);
  }

  onTermInput(data: string): void {
    this.session.input(data);
  }

  onTermResize(cols: number, rows: number): void {
    this.session.resize(cols, rows);
  }

  onTermCtrlConsumed(): void {
    this.ctrlArmed = false;
  }

  dispose(): void {
    this.session.dispose();
  }

  // ---------- internals ----------

  private createBackend(git: GitClient, host: ShellHost): BuiltinShell | VmShell {
    const env = Catalog.environment(this.project.envId);
    const envName = CatalogText.envName(this.project.envId);
    if (env !== undefined && env.isVm) {
      const state = VmManager.state(env.id);
      const engine = state === VmState.READY ? VmManager.createEngine() : null;
      if (engine !== null) {
        this.usingVm = true;
        return new VmShell(engine, this.session.output, {
          envId: env.id, imageDir: VmManager.imageDir(env.id), sharedDir: this.project.path, cols: 0, rows: 0
        }, envName);
      }
      const reason = state === VmState.ENGINE_MISSING ? 'terminal_banner_vm_not_bundled' : 'terminal_banner_vm_missing';
      return new BuiltinShell(this.session.output, host, git, Strings.get(reason, envName));
    }
    return new BuiltinShell(this.session.output, host, git, Strings.get('terminal_banner_no_runtime'));
  }
}
