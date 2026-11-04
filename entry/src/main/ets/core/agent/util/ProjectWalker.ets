import { AgentFs, FsEntry } from '../AgentFs';
import { AgentLimits } from '../AgentLimits';
import { CancelToken } from '../../llm/CancelToken';

/** Depth-first listing of project files, skipping build and dependency folders. */
export class ProjectWalker {
  static isIgnoredDir(name: string): boolean {
    return AgentLimits.IGNORED_DIRS.indexOf(name) >= 0;
  }

  /** Files (not folders) under `dir`, in a stable sorted order, up to `limit`. */
  static async files(fs: AgentFs, dir: string, limit: number, cancel: CancelToken): Promise<FsEntry[]> {
    const out: FsEntry[] = [];
    const stack: string[] = [dir];
    while (stack.length > 0 && out.length < limit) {
      cancel.throwIfCancelled();
      const d = stack.pop() as string;
      let entries: FsEntry[] = [];
      try {
        entries = await fs.list(d);
      } catch (e) {
        continue;
      }
      const subdirs: string[] = [];
      for (const e of entries) {
        if (e.isDir) {
          if (!ProjectWalker.isIgnoredDir(e.name)) {
            subdirs.push(e.path);
          }
        } else {
          out.push(e);
          if (out.length >= limit) {
            break;
          }
        }
      }
      // Reverse so the stack visits folders in sorted order.
      for (let i = subdirs.length - 1; i >= 0; i--) {
        stack.push(subdirs[i]);
      }
    }
    return out;
  }
}
