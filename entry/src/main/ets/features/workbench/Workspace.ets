import { AgentFs } from '../../core/agent/AgentFs';
import { CommandRunner } from '../../core/agent/CommandRunner';
import { PathGuard } from '../../core/agent/PathGuard';
import { WorkspaceKind } from '../../core/agent/SystemPrompt';
import { EventBus, Events } from '../../core/common/EventBus';
import { FileService } from '../../core/fs/FileService';
import { GitClient } from '../../core/git/GitClient';
import { GitChange } from '../../core/git/GitTypes';
import { ProjectInfo } from '../../core/project/ProjectInfo';
import { SearchHit } from '../../core/search/TextSearch';
import { agentSettings } from '../../core/settings/AgentSettingsStore';
import { SettingsStore } from '../../core/settings/SettingsStore';
import { ShellHost } from '../../core/terminal/ShellBackend';
import { AgentHost, AgentModel } from '../agent/AgentModel';
import { BuiltinCommandRunner } from '../agent/host/BuiltinCommandRunner';
import { SandboxAgentFs } from '../agent/host/SandboxAgentFs';
import { VmCommandRunner, VmRunnerHost } from '../agent/host/VmCommandRunner';
import { WorkspaceCommandRunner } from '../agent/host/WorkspaceCommandRunner';
import { CatalogText } from '../app/CatalogText';
import { LayoutState } from '../app/LayoutState';
import { WebTheme } from '../app/WebTheme';
import { CommandService } from '../commands/CommandService';
import { QuickOpenHost, QuickOpenModel } from '../commands/QuickOpenModel';
import { DialogModel } from '../dialogs/DialogModel';
import { ToastModel } from '../dialogs/ToastModel';
import { EditorHost, EditorModel, EditorTheme } from '../editor/EditorModel';
import { ExplorerHost, ExplorerModel } from '../explorer/ExplorerModel';
import { ScmHost, ScmModel } from '../scm/ScmModel';
import { SearchModel } from '../search/SearchModel';
import { TerminalModel } from '../terminal/TerminalModel';
import { registerWorkbenchCommands } from './WorkbenchCommands';
import { OverlayId, SettingsCategory, WorkbenchState } from './WorkbenchState';

/** Shared services a workspace is built from. */
export interface WorkspaceDeps {
  layout: LayoutState;
  git: GitClient;
  settings: SettingsStore;
  dialogs: DialogModel;
  toasts: ToastModel;
}

/**
 * Composition root for one open project: creates each feature model and connects them
 * through small host adapters. Holds no feature logic itself.
 */
export class Workspace {
  readonly project: ProjectInfo;
  readonly deps: WorkspaceDeps;
  readonly bus: EventBus = new EventBus();
  readonly ui: WorkbenchState;
  readonly commands: CommandService = new CommandService();
  readonly editor: EditorModel;
  readonly explorer: ExplorerModel;
  readonly search: SearchModel;
  readonly scm: ScmModel;
  readonly terminal: TerminalModel;
  readonly quickOpen: QuickOpenModel;
  readonly agent: AgentModel;

  constructor(project: ProjectInfo, deps: WorkspaceDeps) {
    this.project = project;
    this.deps = deps;
    this.ui = new WorkbenchState(deps.layout);
    this.editor = new EditorModel(new EditorHostImpl(this));
    this.explorer = new ExplorerModel(project.path, new ExplorerHostImpl(this));
    this.search = new SearchModel(project.path, (hit: SearchHit) => this.editor.openFile(hit.path, hit.line, hit.col));
    this.scm = new ScmModel(project.path, deps.git, new ScmHostImpl(this));
    this.terminal = new TerminalModel(project, deps.git, new ShellHostImpl(this), deps.settings,
      () => WebTheme.terminal());
    this.quickOpen = new QuickOpenModel(project.path, this.commands, new QuickOpenHostImpl(this));
    this.agent = new AgentModel(new AgentHostImpl(this), agentSettings);
    registerWorkbenchCommands(this);
  }

  dispose(): void {
    this.agent.dispose();
    this.editor.dispose();
    this.explorer.dispose();
    this.scm.dispose();
    this.terminal.dispose();
    this.bus.clear();
  }
}

class EditorHostImpl implements EditorHost {
  bus: EventBus;
  dialogs: DialogModel;
  toasts: ToastModel;
  settings: SettingsStore;
  private ws: Workspace;

  constructor(ws: Workspace) {
    this.ws = ws;
    this.bus = ws.bus;
    this.dialogs = ws.deps.dialogs;
    this.toasts = ws.deps.toasts;
    this.settings = ws.deps.settings;
  }

  runCommand(name: string): void {
    this.ws.commands.runShortcut(name);
  }

  revealEditor(): void {
    this.ws.ui.showEditor();
  }

  editorTheme(): EditorTheme {
    return WebTheme.editor();
  }
}

class ExplorerHostImpl implements ExplorerHost {
  bus: EventBus;
  dialogs: DialogModel;
  toasts: ToastModel;
  private ws: Workspace;

  constructor(ws: Workspace) {
    this.ws = ws;
    this.bus = ws.bus;
    this.dialogs = ws.deps.dialogs;
    this.toasts = ws.deps.toasts;
  }

  openFile(path: string): void {
    this.ws.editor.openFile(path);
  }
}

class ScmHostImpl implements ScmHost {
  bus: EventBus;
  dialogs: DialogModel;
  toasts: ToastModel;
  private ws: Workspace;

  constructor(ws: Workspace) {
    this.ws = ws;
    this.bus = ws.bus;
    this.dialogs = ws.deps.dialogs;
    this.toasts = ws.deps.toasts;
  }

  openFile(path: string): void {
    this.ws.editor.openFile(path);
  }

  openDiff(path: string, original: string, modified: string): void {
    this.ws.editor.openDiff(path, original, modified);
  }

  statusChanged(changes: GitChange[]): void {
    // The explorer may not exist yet during construction.
    if (this.ws.explorer !== undefined) {
      this.ws.explorer.setDecorations(changes);
    }
  }
}

class ShellHostImpl implements ShellHost {
  private ws: Workspace;

  constructor(ws: Workspace) {
    this.ws = ws;
  }

  rootDir(): string {
    return this.ws.project.path;
  }

  projectName(): string {
    return this.ws.project.name;
  }

  environmentName(): string {
    return CatalogText.envName(this.ws.project.envId);
  }

  runCommand(): string {
    return this.ws.project.runCommand;
  }

  openFile(path: string): void {
    this.ws.editor.openFile(path);
  }

  filesChanged(path: string): void {
    this.ws.bus.emit(Events.FILES_CHANGED, path);
  }

  gitChanged(): void {
    this.ws.bus.emit(Events.GIT_CHANGED, '');
  }
}

class QuickOpenHostImpl implements QuickOpenHost {
  private ws: Workspace;

  constructor(ws: Workspace) {
    this.ws = ws;
  }

  openFile(path: string): void {
    this.ws.editor.openFile(path);
  }

  gotoLine(line: number): void {
    this.ws.editor.bridge.gotoLine(line, 1);
  }

  close(): void {
    this.ws.ui.overlay = OverlayId.NONE;
  }
}

class AgentHostImpl implements AgentHost, VmRunnerHost {
  private ws: Workspace;
  private agentFs: SandboxAgentFs = new SandboxAgentFs();
  private runner: WorkspaceCommandRunner;
  private guard: PathGuard;

  constructor(ws: Workspace) {
    this.ws = ws;
    this.guard = new PathGuard(ws.project.path, true);
    this.runner = new WorkspaceCommandRunner(new VmCommandRunner(this),
      new BuiltinCommandRunner(new ShellHostImpl(ws), ws.deps.git), () => ws.terminal.usingVm);
  }

  projectId(): string {
    return this.ws.project.id;
  }

  projectName(): string {
    return this.ws.project.name;
  }

  workspaceKind(): string {
    return WorkspaceKind.PROJECT;
  }

  paths(): PathGuard {
    return this.guard;
  }

  fs(): AgentFs {
    return this.agentFs;
  }

  shell(): CommandRunner {
    return this.runner;
  }

  filesChanged(paths: string[]): void {
    for (const p of paths) {
      if (p.length > 0 && !FileService.exists(p)) {
        this.ws.bus.emit(Events.FILE_DELETED, p);
      } else {
        this.ws.bus.emit(Events.FILES_CHANGED, p);
      }
    }
  }

  openFile(path: string): void {
    if (FileService.exists(path) && !FileService.isDir(path)) {
      this.ws.editor.openFile(path);
    }
  }

  openAgentSettings(): void {
    this.ws.ui.openSettings(SettingsCategory.AGENT);
  }

  today(): string {
    const d = new Date();
    const pad = (n: number): string => (n < 10 ? '0' : '') + n;
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  }

  ensureVmStarted(): void {
    // The VM boots when a terminal view attaches to it. On phones the terminal view is already
    // mounted (hidden), so don't take the screen away from the agent there.
    if (!this.ws.deps.layout.isPhone) {
      this.ws.ui.showTerminal();
    }
  }

  environmentName(): string {
    return CatalogText.envName(this.ws.project.envId);
  }
}
