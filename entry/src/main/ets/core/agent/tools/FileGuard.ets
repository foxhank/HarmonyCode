import { ToolInputError } from '../ToolErrors';
import { ToolContext } from '../ToolTypes';

/** Checks shared by tools that change existing files. */
export class FileGuard {
  /**
   * Reads an existing file the agent may edit: it must exist, have been read by the agent, and
   * not have changed since (e.g. the user edited it). Returns the current content.
   */
  static async readForEdit(ctx: ToolContext, path: string): Promise<string> {
    const rel = ctx.paths.rel(path);
    const st = await ctx.fs.stat(path);
    if (st === null || st.isDir) {
      throw new ToolInputError(`File not found: ${rel}. Use write_file to create it.`);
    }
    const before = await ctx.fs.readText(path);
    if (!ctx.reads.hasRead(path)) {
      throw new ToolInputError(`Read ${rel} with read_file before editing it.`);
    }
    if (!ctx.reads.isCurrent(path, before)) {
      throw new ToolInputError(`${rel} changed on disk since you last read it. Read it again, then retry the edit.`);
    }
    return before;
  }
}
