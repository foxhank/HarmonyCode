import { AgentFs } from '../../core/agent/AgentFs';
import { CommandRunner } from '../../core/agent/CommandRunner';
import { PathGuard } from '../../core/agent/PathGuard';
import { WorkspaceKind } from '../../core/agent/SystemPrompt';
import { PathUtil } from '../../core/fs/PathUtil';
import { RemoteCommandRunner } from '../../core/remote/RemoteCommandRunner';
import { ConnState, RemoteConnection } from '../../core/remote/RemoteConnection';
import { RemoteFs } from '../../core/remote/RemoteFs';
import { hostAddress, RemoteHost, RemoteOs } from '../../core/remote/RemoteHost';
import { agentSettings } from '../../core/settings/AgentSettingsStore';
import { SettingsStore } from '../../core/settings/SettingsStore';
import { AgentHost, AgentModel } from '../agent/AgentModel';
import { appNav, Routes } from '../app/AppNavigation';
import { WebTheme } from '../app/WebTheme';
import { DialogModel } from '../dialogs/DialogModel';
import { SettingsCategories } from '../settings/SettingsCategories';
import { ToastModel } from '../dialogs/ToastModel';
import { RemoteFilesModel } from './RemoteFilesModel';
import { RemoteServices } from './RemoteServices';
import { RemoteTerminalModel } from './RemoteTerminal';

/** Tabs of the remote workspace on phones. */
export class RemoteTab {
  static readonly AGENT: string = 'agent';
  static readonly TERMINAL: string = 'terminal';
  static readonly FILES: string = 'files';
}

/** Lets the agent work on the remote computer: full access over SFTP and SSH commands. */
class RemoteAgentHost implements AgentHost {
  private ws: RemoteWorkspace;
  private remoteFs: RemoteFs;
  private runner: RemoteCommandRunner;

  constructor(ws: RemoteWorkspace) {
    this.ws = ws;
    this.remoteFs = new RemoteFs(ws.conn);
    this.runner = new RemoteCommandRunner(ws.conn);
  }

  projectId(): string {
    return 'remote-' + this.ws.host.id;
  }

  projectName(): string {
    return this.ws.host.name + ' (' + hostAddress(this.ws.host) + ')';
  }

  workspaceKind(): string {
    return WorkspaceKind.REMOTE;
  }

  paths(): PathGuard {
    const p = this.ws.conn.platform;
    return new PathGuard(this.ws.conn.startDir(), false, p !== null ? p.home : '');
  }

  fs(): AgentFs {
    return this.remoteFs;
  }

  shell(): CommandRunner {
    return this.runner;
  }

  filesChanged(paths: string[]): void {
    this.ws.files.refresh();
    const doc = this.ws.files.doc;
    if (doc !== null && !doc.dirty && (paths.indexOf(doc.path) >= 0 || paths.indexOf('') >= 0)) {
      this.ws.files.openFile(doc.path);
    }
  }

  openFile(path: string): void {
    this.ws.files.open(PathUtil.dirName(path));
    this.ws.files.openFile(path);
    this.ws.tab = RemoteTab.FILES;
  }

  openAgentSettings(): void {
    appNav.pushPathByName(Routes.SETTINGS, SettingsCategories.AGENT);
  }

  today(): string {
    const d = new Date();
    const pad = (n: number): string => (n < 10 ? '0' : '') + n;
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  }
}

/**
 * Composition root for one remote computer: one connection shared by the agent, the terminal
 * and the file browser.
 */
@ObservedV2
export class RemoteWorkspace {
  readonly host: RemoteHost;
  readonly conn: RemoteConnection;
  readonly terminal: RemoteTerminalModel;
  readonly files: RemoteFilesModel;
  readonly agent: AgentModel;
  @Trace state: string = ConnState.IDLE;
  @Trace error: string = '';
  /** Description of the machine once known, e.g. "Ubuntu 24.04 LTS · pc". */
  @Trace platform: string = '';
  @Trace tab: string = RemoteTab.AGENT;
  /** The first connection succeeded (the agent needs the platform to start). */
  @Trace ready: boolean = false;
  private offState: () => void;

  constructor(host: RemoteHost, settings: SettingsStore, dialogs: DialogModel, toasts: ToastModel) {
    this.host = host;
    this.conn = RemoteServices.connection(host);
    this.terminal = new RemoteTerminalModel(this.conn, settings, () => WebTheme.terminal());
    this.files = new RemoteFilesModel(new RemoteFs(this.conn), dialogs, toasts);
    this.agent = new AgentModel(new RemoteAgentHost(this), agentSettings);
    this.offState = this.conn.onChange((state: string, error: string) => {
      this.state = state;
      this.error = error;
    });
  }

  get isWindows(): boolean {
    return this.conn.platform !== null && this.conn.platform.os === RemoteOs.WINDOWS;
  }

  async connect(): Promise<void> {
    try {
      await this.conn.connect();
    } catch (e) {
      return;
    }
    const p = this.conn.platform;
    if (p !== null) {
      this.platform = [p.release, p.hostname].filter((s: string) => s.length > 0).join(' · ');
    }
    if (!this.ready) {
      this.ready = true;
      this.files.open(this.conn.startDir());
    }
  }

  dispose(): void {
    this.offState();
    this.agent.dispose();
    this.terminal.dispose();
    this.conn.close();
  }
}
