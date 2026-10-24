import { Strings } from '../../common/Strings';
import { errorMessage } from '../../common/Logger';
import { FileService } from '../../fs/FileService';
import { PathUtil } from '../../fs/PathUtil';
import { GitClient } from '../../git/GitClient';
import { Ansi } from '../Ansi';
import { OutputSink, ShellBackend, ShellHost } from '../ShellBackend';
import { tokenize } from './ArgParser';
import { fsCommands } from './FsCommands';
import { gitCommands } from './GitCommands';
import { Completion, LineEditor } from './LineEditor';
import { CommandRegistry, Exit, ShellCommand, ShellContext, ShellIO } from './ShellCommand';

const HOME: string = '~';

/** ShellIO that writes to the terminal output with CRLF line endings. */
class SinkIO implements ShellIO {
  private out: OutputSink;

  constructor(out: OutputSink) {
    this.out = out;
  }

  write(text: string): void {
    this.out(text);
  }

  writeln(text: string): void {
    this.out(text + Ansi.CRLF);
  }

  error(text: string): void {
    this.out(Ansi.red(text) + Ansi.CRLF);
  }
}

/**
 * A small shell that runs inside the app (no VM): file commands, Git, open-in-editor.
 * Used when the project's Linux environment isn't available.
 */
export class BuiltinShell implements ShellBackend, ShellContext {
  readonly io: ShellIO;
  readonly host: ShellHost;
  readonly git: GitClient;
  private out: OutputSink;
  private registry: CommandRegistry;
  private editor: LineEditor;
  private cwdPath: string;
  private banner: string;

  /** `banner` is printed once at start (e.g. why the VM isn't being used). */
  constructor(out: OutputSink, host: ShellHost, git: GitClient, banner: string) {
    this.out = out;
    this.host = host;
    this.git = git;
    this.banner = banner;
    this.cwdPath = host.rootDir();
    this.registry = new CommandRegistry().register(fsCommands()).register(gitCommands());
    this.io = new SinkIO(out);
    this.editor = new LineEditor(out, (line: string) => this.execute(line),
      (before: string) => this.completeLine(before));
  }

  // ---- ShellBackend ----

  label(): string {
    return Strings.get('terminal_builtin_label');
  }

  start(cols: number, rows: number): void {
    if (this.banner.length > 0) {
      this.out(Ansi.crlf(this.banner) + Ansi.CRLF + Ansi.CRLF);
    }
    this.prompt();
  }

  input(data: string): void {
    this.editor.feed(data, () => this.out('^C' + Ansi.CRLF));
  }

  resize(cols: number, rows: number): void {
    // Line editing redraws on the next keystroke; nothing to do.
  }

  runLine(line: string): void {
    if (!this.editor.isActive()) {
      return;
    }
    this.out(line + Ansi.CRLF);
    this.execute(line);
  }

  stop(): void {
    // Nothing to release.
  }

  // ---- ShellContext ----

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
    if (path === this.home()) {
      return HOME;
    }
    return rel !== path ? HOME + '/' + rel : path;
  }

  commands(): ShellCommand[] {
    return this.registry.all();
  }

  clear(): void {
    this.out(Ansi.CLEAR_SCREEN);
  }

  // ---- internals ----

  private prompt(): void {
    const p = Ansi.boldGreen(this.host.projectName()) + ':' + Ansi.boldBlue(this.display(this.cwdPath)) + '$ ';
    this.editor.showPrompt(p);
  }

  private execute(line: string): void {
    const words = tokenize(line.trim());
    if (words.length === 0) {
      this.prompt();
      return;
    }
    const cmd = this.registry.get(words[0]);
    if (cmd === undefined) {
      this.io.error(Strings.get('sh_err_command_not_found', words[0]));
      this.prompt();
      return;
    }
    cmd.run(this, words.slice(1)).catch((e: Error) => {
      this.io.error(errorMessage(e));
      return Exit.FAIL;
    }).finally(() => this.prompt());
  }

  /** Completes a command name (first word) or a path (later words). */
  private completeLine(before: string): Completion {
    const lastSpace = before.lastIndexOf(' ');
    const word = before.substring(lastSpace + 1);
    let candidates: string[];
    if (lastSpace < 0) {
      candidates = this.registry.names().filter((n: string) => n.startsWith(word)).map((n: string) => n + ' ');
    } else {
      candidates = this.pathCandidates(word);
    }
    if (candidates.length === 0) {
      return { insert: '', candidates: [] };
    }
    const common = BuiltinShell.commonPrefix(candidates);
    const typed = word.substring(word.lastIndexOf('/') + 1);
    const insert = lastSpace < 0 ? common.substring(word.length) : common.substring(typed.length);
    return { insert: insert, candidates: candidates };
  }

  private pathCandidates(word: string): string[] {
    const slash = word.lastIndexOf('/');
    const dirPart = slash >= 0 ? word.substring(0, slash + 1) : '';
    const prefix = word.substring(slash + 1);
    const dir = this.resolve(dirPart.length > 0 ? dirPart : '.');
    return FileService.list(dir, prefix.startsWith('.'))
      .filter((e) => e.name.startsWith(prefix))
      .map((e) => e.isDir ? e.name + '/' : e.name + ' ');
  }

  private static commonPrefix(list: string[]): string {
    let p = list[0];
    for (const s of list) {
      while (!s.startsWith(p)) {
        p = p.substring(0, p.length - 1);
      }
    }
    return p;
  }
}
