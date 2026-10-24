import { PathUtil } from '../../core/fs/PathUtil';

const DIFF_PREFIX: string = 'diff:';

/** One open editor tab. Text lives here so tabs survive the web view being rebuilt. */
@ObservedV2
export class EditorTab {
  @Trace id: string;
  @Trace path: string;
  @Trace title: string;
  @Trace dirty: boolean = false;
  @Trace isDiff: boolean = false;
  /** Latest text reported by the editor. */
  text: string = '';
  /** Text as last read from / written to disk. */
  savedText: string = '';
  /** For diff tabs: the "before" side (HEAD). */
  diffOriginal: string = '';

  constructor(path: string, isDiff: boolean) {
    this.id = isDiff ? DIFF_PREFIX + path : path;
    this.path = path;
    this.title = PathUtil.baseName(path);
    this.isDiff = isDiff;
  }

  static diffId(path: string): string {
    return DIFF_PREFIX + path;
  }

  /** Moves the tab to a new path (after rename). */
  retarget(path: string): void {
    this.id = this.isDiff ? DIFF_PREFIX + path : path;
    this.path = path;
    this.title = PathUtil.baseName(path);
  }
}
