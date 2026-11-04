import { CommandResult, CommandRunner, OutputListener } from '../../../core/agent/CommandRunner';
import { errorMessage } from '../../../core/common/Logger';
import { PathUtil } from '../../../core/fs/PathUtil';
import { GitClient } from '../../../core/git/GitClient';
import { CancelToken } from '../../../core/llm/CancelToken';
import { ShellHost } from '../../../core/terminal/ShellBackend';
import { tokenize } from '../../../core/terminal/builtin/ArgParser';
import { fsCommands } from '../../../core/terminal/builtin/FsCommands';
import { gitCommands } from '../../../core/terminal/builtin/GitCommands';
import { CommandRegistry, Exit, ShellCommand, ShellContext, ShellIO } from '../../../core/terminal/builtin/ShellCommand';
import { CommandLine, CommandStep } from './CommandLine';

/** Commands that only make sense in an interactive terminal. */
const INTERACTIVE_ONLY: string[] = ['clear', 'open', 'help', 'run'];

/** Collects command output as plain text (LF line endings) and forwards it live. */
class CaptureIO implements ShellIO {
  text: string = '';
  private live: OutputListener;

  constructor(live: OutputListener) {
    this.live = live;
  }

  write(text: string): void {
    this.add(text);
  }

  writeln(text: string): void {
    this.add(text + '\n');
  }

  error(text: string): void {
    this.add(text + '\n');
  }

  private add(t: string): void {
    this.text += t;
    this.live(t);
  }
}

/** A ShellContext for one agent command: own cwd, captured output. */
class HeadlessContext implements ShellContext {
  io: CaptureIO;
  host: ShellHost;
  git: GitClient;
  private cwdPath: string;
  private registry: CommandRegistry;

  constructor(io: CaptureIO, host: ShellHost, git: GitClient, cwd: string, registry: CommandRegistry) {
    this.io = io;
    this.host = host;
    this.git = git;
    this.cwdPath = cwd;
    this.registry = registry;
  }

  cwd(): string {
    return this.cwdPath;
  }

  setCwd(path: string): void {
    this.cwdPath = path;
  }

  home(): string {
    return this.host.rootDir();
  }

  resolve(input: string): string {
    return PathUtil.resolve(this.cwdPath, input, this.home());
  }

  display(path: string): string {
    const rel = PathUtil.relative(this.home(), path);
    return path === this.home() ? '.' : rel;
  }

  commands(): ShellCommand[] {
    return this.registry.all();
  }

  clear(): void {
    // Nothing to clear without a terminal.
  }
}

/**
 * Runs agent commands with the in-app shell (file commands and Git) when the project's Linux VM
 * isn't running. Supports `;`, `&&` and `||`; tells the model plainly what isn't available.
 */
export class BuiltinCommandRunner implements CommandRunner {
  private host: ShellHost;
  private git: GitClient;
  private registry: CommandRegistry;

  constructor(host: ShellHost, git: GitClient) {
    this.host = host;
    this.git = git;
    this.registry = new CommandRegistry().register(fsCommands()).register(gitCommands());
  }

  describe(): string {
    const names = this.registry.names().filter((n: string) => INTERACTIVE_ONLY.indexOf(n) < 0);
    return 'HarmonyCode built-in shell, because the project\'s Linux environment is not running. It is NOT a ' +
      'POSIX shell: only these commands exist: ' + names.join(', ') + ' (git supports status, add, commit, ' +
      'log, branch, checkout, pull, push, clone). Commands can be chained with ;, && and ||; pipes, ' +
      'redirection, variables and globs are not supported. No compilers or interpreters (python, node, gcc, ' +
      '...) are available, so code cannot be executed here; tell the user that running code needs the ' +
      'project\'s Linux environment (Settings › Compiler › Linux environments) and an open terminal.';
  }

  async run(command: string, cwd: string, timeoutMs: number, cancel: CancelToken,
    onOutput: OutputListener): Promise<CommandResult> {
    const io = new CaptureIO(onOutput);
    const unsupported = CommandLine.unsupportedFeature(command);
    if (unsupported.length > 0) {
      io.error(`built-in shell: ${unsupported} not supported`);
      return { exitCode: Exit.USAGE, output: io.text, timedOut: false };
    }
    const ctx = new HeadlessContext(io, this.host, this.git, cwd, this.registry);
    let timedOut = false;
    const work = this.runSteps(CommandLine.split(command), ctx, cancel);
    const limit = new Promise<number>((resolve: (n: number) => void) => {
      const timer = setTimeout(() => {
        timedOut = true;
        resolve(-1);
      }, timeoutMs);
      const off = cancel.onCancel(() => {
        clearTimeout(timer);
        resolve(-1);
      });
      work.finally(() => {
        clearTimeout(timer);
        off();
      });
    });
    const code = await Promise.race([work, limit]);
    cancel.throwIfCancelled();
    return { exitCode: code, output: io.text, timedOut: timedOut };
  }

  private async runSteps(steps: CommandStep[], ctx: HeadlessContext, cancel: CancelToken): Promise<number> {
    let last = Exit.OK;
    for (const step of steps) {
      if (cancel.cancelled) {
        return -1;
      }
      if ((step.op === '&&' && last !== Exit.OK) || (step.op === '||' && last === Exit.OK)) {
        continue;
      }
      last = await this.runOne(step.text, ctx);
    }
    return last;
  }

  private async runOne(text: string, ctx: HeadlessContext): Promise<number> {
    const words = tokenize(text);
    if (words.length === 0) {
      return Exit.OK;
    }
    const cmd = this.registry.get(words[0]);
    if (cmd === undefined || INTERACTIVE_ONLY.indexOf(words[0]) >= 0) {
      ctx.io.error(`${words[0]}: command not found in the built-in shell`);
      return Exit.NOT_FOUND;
    }
    try {
      return await cmd.run(ctx, words.slice(1));
    } catch (e) {
      ctx.io.error(errorMessage(e as Error));
      return Exit.FAIL;
    }
  }
}
