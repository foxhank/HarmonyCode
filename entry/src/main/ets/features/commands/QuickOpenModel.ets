import { AppConfig } from '../../core/common/AppConfig';
import { Strings } from '../../core/common/Strings';
import { FileService } from '../../core/fs/FileService';
import { PathUtil } from '../../core/fs/PathUtil';
import { Fuzzy } from '../../core/search/Fuzzy';
import { CommandService, WorkbenchCommand } from './CommandService';

const COMMAND_PREFIX: string = '>';
const LINE_PREFIX: string = ':';

export class QuickKind {
  static readonly FILE: string = 'file';
  static readonly COMMAND: string = 'command';
  static readonly LINE: string = 'line';
}

export interface QuickItem {
  id: string;
  label: string;
  detail: string;
  kind: string;
}

export interface QuickOpenHost {
  openFile(path: string): void;
  gotoLine(line: number): void;
  close(): void;
}

/** Ctrl+P: files by default, commands after '>', go to line after ':'. */
@ObservedV2
export class QuickOpenModel {
  @Trace query: string = '';
  @Trace items: QuickItem[] = [];
  @Trace selected: number = 0;
  private root: string;
  private commands: CommandService;
  private host: QuickOpenHost;
  private files: string[] = [];

  constructor(root: string, commands: CommandService, host: QuickOpenHost) {
    this.root = root;
    this.commands = commands;
    this.host = host;
  }

  get placeholderKey(): string {
    return this.query.startsWith(COMMAND_PREFIX) ? 'quick_placeholder_commands' : 'quick_placeholder_files';
  }

  showFiles(): void {
    this.files = FileService.walk(this.root, AppConfig.QUICK_OPEN_MAX_FILES)
      .map((p: string) => PathUtil.relative(this.root, p));
    this.setQuery('');
  }

  showCommands(): void {
    this.setQuery(COMMAND_PREFIX);
  }

  setQuery(q: string): void {
    this.query = q;
    this.selected = 0;
    if (q.startsWith(COMMAND_PREFIX)) {
      this.items = this.commandItems(q.substring(COMMAND_PREFIX.length).trim());
    } else if (q.startsWith(LINE_PREFIX)) {
      const n = Number(q.substring(LINE_PREFIX.length).trim());
      this.items = Number.isInteger(n) && n > 0 ?
        [{ id: n.toString(), label: Strings.get('quick_goto_line', n), detail: '', kind: QuickKind.LINE }] : [];
    } else {
      this.items = this.fileItems(q.trim());
    }
  }

  move(delta: number): void {
    if (this.items.length === 0) {
      return;
    }
    this.selected = (this.selected + delta + this.items.length) % this.items.length;
  }

  accept(index: number = this.selected): void {
    const item = this.items[index];
    if (item === undefined) {
      return;
    }
    this.host.close();
    if (item.kind === QuickKind.FILE) {
      this.host.openFile(PathUtil.join(this.root, item.id));
    } else if (item.kind === QuickKind.LINE) {
      this.host.gotoLine(Number(item.id));
    } else {
      this.commands.run(item.id);
    }
  }

  private fileItems(q: string): QuickItem[] {
    const ranked = q.length === 0 ? this.files.slice(0, AppConfig.QUICK_OPEN_MAX_RESULTS) :
      Fuzzy.rank(q, this.files, (f: string) => f, AppConfig.QUICK_OPEN_MAX_RESULTS);
    return ranked.map((rel: string): QuickItem => {
      const dir = PathUtil.dirName(rel);
      return { id: rel, label: PathUtil.baseName(rel), detail: rel.indexOf('/') >= 0 ? dir : '', kind: QuickKind.FILE };
    });
  }

  private commandItems(q: string): QuickItem[] {
    const all = this.commands.all();
    const ranked = q.length === 0 ? all : Fuzzy.rank(q, all, (c: WorkbenchCommand) => this.commands.title(c),
      all.length);
    return ranked.map((c: WorkbenchCommand): QuickItem => {
      return { id: c.id, label: this.commands.title(c), detail: c.keys, kind: QuickKind.COMMAND };
    });
  }
}
