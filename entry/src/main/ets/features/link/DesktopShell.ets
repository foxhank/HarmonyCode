import { CommandRunner } from '../../core/agent/CommandRunner';
import { PathUtil } from '../../core/fs/PathUtil';
import { CancelToken } from '../../core/llm/CancelToken';
import { Strings } from '../../core/common/Strings';
import { OutputSink, ShellBackend } from '../../core/terminal/ShellBackend';

const PROMPT_COLOR: string = '\x1b[36m';
const DIM: string = '\x1b[2m';
const RESET: string = '\x1b[0m';
const NL: string = '\r\n';
const TIMEOUT_MS: number = 60 * 60 * 1000;
const HISTORY_MAX: number = 100;

/**
 * A line-mode terminal on the paired desktop: each line runs there as a command (with sync before
 * and after), `cd` moves within the project, Ctrl+C stops the running command. Programs that need
 * a full-screen terminal (vim, top) are not supported over Link; use an SSH computer for those.
 */
export class DesktopShellBackend implements ShellBackend {
  private runner: CommandRunner;
  private sink: OutputSink;
  private root: string;
  private cwd: string;
  private name: string;
  private line: string = '';
  private running: CancelToken | null = null;
  private history: string[] = [];
  private historyPos: number = 0;
  private escape: string = '';

  constructor(runner: CommandRunner, sink: OutputSink, projectRoot: string, desktopName: string) {
    this.runner = runner;
    this.sink = sink;
    this.root = projectRoot;
    this.cwd = projectRoot;
    this.name = desktopName;
  }

  label(): string {
    return this.name;
  }

  start(cols: number, rows: number): void {
    this.sink(DIM + Strings.get('link_term_banner', this.name) + RESET + NL);
    this.prompt();
  }

  input(data: string): void {
    for (const ch of data) {
      this.key(ch);
    }
  }

  resize(cols: number, rows: number): void {
  }

  runLine(line: string): void {
    if (this.running !== null) {
      return;
    }
    this.line = line;
    this.sink(line + NL);
    this.execute();
  }

  stop(): void {
    this.running?.cancel();
  }

  private key(ch: string): void {
    if (this.escape.length > 0) {
      this.escape += ch;
      if (this.escape.length >= 3) {
        const seq = this.escape;
        this.escape = '';
        if (seq === '\x1b[A' || seq === '\x1b[B') {
          this.recall(seq === '\x1b[A' ? -1 : 1);
        }
      }
      return;
    }
    if (ch === '\x03') {
      if (this.running !== null) {
        this.running.cancel();
        this.sink('^C' + NL);
      } else {
        this.line = '';
        this.sink('^C' + NL);
        this.prompt();
      }
      return;
    }
    if (this.running !== null) {
      return; // commands get no input over Link
    }
    if (ch === '\x1b') {
      this.escape = ch;
    } else if (ch === '\r' || ch === '\n') {
      this.sink(NL);
      this.execute();
    } else if (ch === '\x7f' || ch === '\b') {
      if (this.line.length > 0) {
        this.line = this.line.substring(0, this.line.length - 1);
        this.sink('\b \b');
      }
    } else if (ch >= ' ') {
      this.line += ch;
      this.sink(ch);
    }
  }

  private recall(dir: number): void {
    if (this.history.length === 0) {
      return;
    }
    this.historyPos = Math.max(0, Math.min(this.history.length, this.historyPos + dir));
    const next = this.historyPos < this.history.length ? this.history[this.historyPos] : '';
    this.sink('\b \b'.repeat(this.line.length));
    this.line = next;
    this.sink(next);
  }

  private prompt(): void {
    const rel = PathUtil.relative(this.root, this.cwd);
    this.sink(PROMPT_COLOR + this.name + ':' + (rel.length > 0 ? rel : '.') + RESET + ' $ ');
  }

  private async execute(): Promise<void> {
    const cmd = this.line.trim();
    this.line = '';
    if (cmd.length === 0) {
      this.prompt();
      return;
    }
    this.history.push(cmd);
    if (this.history.length > HISTORY_MAX) {
      this.history.shift();
    }
    this.historyPos = this.history.length;
    if (cmd === 'clear' || cmd === 'cls') {
      this.sink('\x1b[2J\x1b[H');
      this.prompt();
      return;
    }
    if (cmd === 'cd' || cmd.startsWith('cd ')) {
      this.changeDir(cmd.substring(2).trim());
      this.prompt();
      return;
    }
    const cancel = new CancelToken();
    this.running = cancel;
    try {
      const r = await this.runner.run(cmd, this.cwd, TIMEOUT_MS, cancel, (t: string) => {
        this.sink(t.replace(new RegExp('\\r?\\n', 'g'), NL));
      });
      if (r.exitCode !== 0) {
        this.sink(NL + DIM + Strings.get('link_term_exit', r.exitCode) + RESET + NL);
      }
    } catch (e) {
      if (!CancelToken.isCancellation(e as Error)) {
        this.sink('\x1b[31m' + (e as Error).message + RESET + NL);
      }
    } finally {
      this.running = null;
    }
    this.prompt();
  }

  private changeDir(arg: string): void {
    const target = arg.length === 0 || arg === '~' ? this.root :
      PathUtil.resolve(this.cwd, arg.replace(new RegExp('^["\']|["\']$', 'g'), ''), this.root);
    if (!PathUtil.isInside(this.root, target)) {
      this.sink(Strings.get('link_term_cd_outside') + NL);
      return;
    }
    this.cwd = target;
  }
}
