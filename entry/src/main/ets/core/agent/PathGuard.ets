import { PathUtil } from '../fs/PathUtil';
import { ToolInputError } from './ToolErrors';

const DRIVE: RegExp = new RegExp('^[A-Za-z]:(/|$)');

/**
 * Resolves the paths the model gives. In a project the agent is confined to the project folder;
 * on a remote machine it has full access (`confined` = false) and relative paths start at `root`.
 */
export class PathGuard {
  readonly root: string;
  readonly confined: boolean;
  /** What `~` means ('' = the root). */
  readonly home: string;

  constructor(root: string, confined: boolean, home: string = '') {
    this.root = root;
    this.confined = confined;
    this.home = home.length > 0 ? home : root;
  }

  /** Absolute path for `input`. Throws ToolInputError when confined and the path leaves the root. */
  resolve(input: string): string {
    let p = input.trim();
    if (p.length === 0 || p === '.' || p === './') {
      return this.root;
    }
    // Windows-style separators and drive letters ("C:\Users" -> "/C:/Users", how SFTP names them).
    p = p.replace(new RegExp('\\\\', 'g'), '/');
    if (DRIVE.test(p)) {
      p = '/' + p;
    }
    const abs = PathUtil.resolve(this.root, p, this.home);
    if (this.confined && !PathUtil.isInside(this.root, abs)) {
      throw new ToolInputError(`Path "${input}" is outside the project. Use a path relative to the project root.`);
    }
    return abs;
  }

  /** Root-relative display form ('.' for the root); absolute outside the root. */
  rel(abs: string): string {
    return PathGuard.relTo(this.root, abs);
  }

  static relTo(base: string, abs: string): string {
    const r = PathUtil.relative(base, abs);
    return r.length === 0 ? '.' : r;
  }
}
