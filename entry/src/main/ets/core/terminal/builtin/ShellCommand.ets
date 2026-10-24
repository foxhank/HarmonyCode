import { GitClient } from '../../git/GitClient';
import { ShellHost } from '../ShellBackend';

/** Output helpers for commands (all text is written with CRLF line endings). */
export interface ShellIO {
  write(text: string): void;
  writeln(text: string): void;
  error(text: string): void;
}

/** Everything a command may use. Commands never touch UI code directly. */
export interface ShellContext {
  io: ShellIO;
  host: ShellHost;
  git: GitClient;
  /** Current directory (absolute path). */
  cwd(): string;
  setCwd(path: string): void;
  /** Project root; '~' expands to this. */
  home(): string;
  /** Absolute path for a user-typed path. */
  resolve(input: string): string;
  /** Path to show the user: '~/src/x' style. */
  display(path: string): string;
  commands(): ShellCommand[];
  clear(): void;
}

/** Exit codes. */
export class Exit {
  static readonly OK: number = 0;
  static readonly FAIL: number = 1;
  static readonly USAGE: number = 2;
  static readonly NOT_FOUND: number = 127;
}

export type CommandFn = (ctx: ShellContext, args: string[]) => Promise<number>;

export interface ShellCommand {
  readonly name: string;
  /** String resource name with a one-line description. */
  readonly summaryKey: string;
  run(ctx: ShellContext, args: string[]): Promise<number>;
}

/** A command defined by a function. */
export class FnCommand implements ShellCommand {
  readonly name: string;
  readonly summaryKey: string;
  private fn: CommandFn;

  constructor(name: string, summaryKey: string, fn: CommandFn) {
    this.name = name;
    this.summaryKey = summaryKey;
    this.fn = fn;
  }

  run(ctx: ShellContext, args: string[]): Promise<number> {
    return this.fn(ctx, args);
  }
}

/** Name -> command lookup. */
export class CommandRegistry {
  private map: Map<string, ShellCommand> = new Map();

  register(cmds: ShellCommand[]): CommandRegistry {
    for (const c of cmds) {
      this.map.set(c.name, c);
    }
    return this;
  }

  get(name: string): ShellCommand | undefined {
    return this.map.get(name);
  }

  all(): ShellCommand[] {
    return Array.from(this.map.values()).sort((a: ShellCommand, b: ShellCommand) => a.name.localeCompare(b.name));
  }

  names(): string[] {
    return this.all().map((c: ShellCommand) => c.name);
  }
}
