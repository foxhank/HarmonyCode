import { CommandResult, CommandRunner } from '../../core/agent/CommandRunner';
import { TextLimits } from '../../core/agent/util/TextLimits';
import { Strings } from '../../core/common/Strings';
import { CancelToken } from '../../core/llm/CancelToken';
import { Catalog, EnvironmentDef, ToolDef } from '../../core/project/Catalog';

const PROBE_TIMEOUT_MS: number = 60000;
/** Package installs over a phone connection inside an emulated VM can be slow. */
const INSTALL_TIMEOUT_MS: number = 30 * 60 * 1000;
const LOG_MAX_CHARS: number = 40000;
const MARK: string = 'HCTOOL ';
const MISSING: string = '-';

/** What the agent is told is installed, per environment (filled when the tools page checks). */
export class InstalledTools {
  private static byEnv: Map<string, string> = new Map();

  static set(envId: string, summary: string): void {
    InstalledTools.byEnv.set(envId, summary);
  }

  /** e.g. "Python 3.12.8, Node.js v22.11.0" ('' when unknown). */
  static summary(envId: string): string {
    const s = InstalledTools.byEnv.get(envId);
    return s !== undefined ? s : '';
  }
}

/** One tool's row on the page. */
@ObservedV2
export class ToolState {
  readonly def: ToolDef;
  /** First line of its version output; '' when not installed. */
  @Trace version: string = '';
  @Trace known: boolean = false;

  constructor(def: ToolDef) {
    this.def = def;
  }

  get installed(): boolean {
    return this.version.length > 0;
  }

  get name(): string {
    return Strings.get('tool_' + this.def.id + '_name');
  }
}

/**
 * The project environment's "Languages and tools": what is installed in its Linux VM, and
 * one-tap install / remove through the distribution's package manager, with live output.
 */
@ObservedV2
export class ToolsModel {
  @Trace tools: ToolState[] = [];
  @Trace checking: boolean = false;
  /** Id of the tool being installed or removed ('' = none). */
  @Trace busyId: string = '';
  @Trace log: string = '';
  @Trace error: string = '';
  private env: EnvironmentDef;
  private runner: CommandRunner;
  private cwd: string;
  private cancel: CancelToken | null = null;

  constructor(env: EnvironmentDef, runner: CommandRunner, cwd: string) {
    this.env = env;
    this.runner = runner;
    this.cwd = cwd;
    this.tools = Catalog.tools().map((t: ToolDef) => new ToolState(t));
  }

  get busy(): boolean {
    return this.busyId.length > 0 || this.checking;
  }

  /** Detects every tool's version with one command. */
  async refresh(): Promise<void> {
    if (this.checking) {
      return;
    }
    this.checking = true;
    this.error = '';
    try {
      const r = await this.runner.run(ToolsModel.probeScript(this.tools), this.cwd, PROBE_TIMEOUT_MS, new CancelToken(),
        () => {
        });
      const found = ToolsModel.parse(TextLimits.stripAnsi(r.output));
      for (const t of this.tools) {
        const v = found.get(t.def.id);
        t.version = v !== undefined && v !== MISSING ? v : '';
        t.known = v !== undefined;
      }
      if (found.size === 0) {
        this.error = r.output.trim().length > 0 ? TextLimits.middle(r.output.trim(), 400) : Strings.get('tools_check_failed');
      }
      InstalledTools.set(this.env.id, this.tools.filter((t: ToolState) => t.installed)
        .map((t: ToolState) => t.name + ' (' + t.version + ')').join(', '));
    } catch (e) {
      this.error = (e as Error).message;
    } finally {
      this.checking = false;
    }
  }

  install(t: ToolState): Promise<void> {
    return this.runPackages(t, Catalog.toolInstallCommand(this.env, t.def));
  }

  remove(t: ToolState): Promise<void> {
    return this.runPackages(t, Catalog.toolRemoveCommand(this.env, t.def));
  }

  stop(): void {
    this.cancel?.cancel();
  }

  private async runPackages(t: ToolState, command: string): Promise<void> {
    if (this.busy || command.length === 0) {
      return;
    }
    this.busyId = t.def.id;
    this.error = '';
    this.log = '$ ' + command + '\n';
    const cancel = new CancelToken();
    this.cancel = cancel;
    try {
      const r: CommandResult = await this.runner.run(command, this.cwd, INSTALL_TIMEOUT_MS, cancel, (chunk: string) => {
        this.log = (this.log + TextLimits.stripAnsi(chunk)).slice(-LOG_MAX_CHARS);
      });
      if (r.exitCode !== 0) {
        this.error = r.timedOut ? Strings.get('tools_timed_out') : Strings.get('tools_failed', r.exitCode);
      }
    } catch (e) {
      this.error = CancelToken.isCancellation(e as Error) ? Strings.get('tools_stopped') : (e as Error).message;
    } finally {
      this.cancel = null;
      this.busyId = '';
    }
    await this.refresh();
  }

  /** One `HCTOOL <id> <version or ->` line per tool. Plain POSIX sh. */
  static probeScript(tools: ToolState[]): string {
    return tools.map((t: ToolState) => {
      const id = t.def.id;
      return `if command -v ${t.def.bin} >/dev/null 2>&1; then printf '${MARK}${id} %s\\n' "$(${t.def.version} 2>&1 | ` +
        `head -n 1)"; else echo '${MARK}${id} ${MISSING}'; fi`;
    }).join('; ');
  }

  static parse(output: string): Map<string, string> {
    const out: Map<string, string> = new Map();
    for (const raw of output.split('\n')) {
      const line = raw.trim();
      if (!line.startsWith(MARK)) {
        continue;
      }
      const rest = line.substring(MARK.length);
      const sp = rest.indexOf(' ');
      if (sp > 0) {
        out.set(rest.substring(0, sp), rest.substring(sp + 1).trim());
      }
    }
    return out;
  }
}
