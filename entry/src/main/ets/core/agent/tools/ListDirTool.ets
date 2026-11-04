import { ToolSpec } from '../../llm/LlmTypes';
import { FsEntry } from '../AgentFs';
import { AgentLimits } from '../AgentLimits';
import { AgentTool, ToolArgs, ToolContext, ToolInputError, ToolKind, ToolLabel, ToolOutput } from '../ToolTypes';
import { ProjectWalker } from '../util/ProjectWalker';
import { Schema } from './Schema';

/** Shows a folder as an indented tree. */
export class ListDirTool implements AgentTool {
  readonly kind: string = ToolKind.READ;
  readonly spec: ToolSpec = {
    name: 'list_dir',
    description: 'List files and folders as a tree. Folders end with "/"; files show their size. ' +
      'Dependency and build folders (node_modules, .git, build, ...) are shown but not expanded.',
    parameters: Schema.object({
      'path': Schema.str('Folder (relative to the working folder, or absolute). Default: the working folder.'),
      'depth': Schema.int('How many levels to expand (1-' + AgentLimits.LIST_MAX_DEPTH + '). Default 2.')
    }, [])
  };

  label(args: ToolArgs): ToolLabel {
    return { verbKey: 'agent_tool_list', target: args.optStr('path', '.') };
  }

  async preview(args: ToolArgs, ctx: ToolContext): Promise<string> {
    return '';
  }

  async run(args: ToolArgs, ctx: ToolContext): Promise<ToolOutput> {
    const dir = ctx.paths.resolve(args.optStr('path', '.'));
    const st = await ctx.fs.stat(dir);
    if (st === null) {
      throw new ToolInputError('No such folder: ' + ctx.paths.rel(dir));
    }
    if (!st.isDir) {
      throw new ToolInputError('Not a folder: ' + ctx.paths.rel(dir) + ' (use read_file for files)');
    }
    const depth = Math.max(1, Math.min(AgentLimits.LIST_MAX_DEPTH, Math.floor(args.optNum('depth', 2))));
    const lines: string[] = [ctx.paths.rel(dir) + '/'];
    const state = new ListState();
    await this.walk(ctx, dir, 1, depth, '  ', lines, state);
    if (state.truncated) {
      lines.push(`[listing stopped at ${AgentLimits.LIST_MAX_ENTRIES} entries; list a subfolder for more]`);
    }
    return ToolOutput.ok(lines.join('\n'));
  }

  private async walk(ctx: ToolContext, dir: string, level: number, maxDepth: number, indent: string,
    lines: string[], state: ListState): Promise<void> {
    ctx.cancel.throwIfCancelled();
    let entries: FsEntry[] = [];
    try {
      entries = await ctx.fs.list(dir);
    } catch (e) {
      lines.push(indent + '[unreadable]');
      return;
    }
    for (const e of entries) {
      if (state.count >= AgentLimits.LIST_MAX_ENTRIES) {
        state.truncated = true;
        return;
      }
      state.count++;
      if (e.isDir) {
        const skip = ProjectWalker.isIgnoredDir(e.name);
        lines.push(indent + e.name + '/' + (skip ? ' [not expanded]' : ''));
        if (!skip && level < maxDepth) {
          await this.walk(ctx, e.path, level + 1, maxDepth, indent + '  ', lines, state);
        }
      } else {
        lines.push(indent + e.name + ' (' + ListDirTool.size(e.size) + ')');
      }
    }
  }

  private static size(bytes: number): string {
    if (bytes < 1024) {
      return bytes + ' B';
    }
    if (bytes < 1024 * 1024) {
      return (bytes / 1024).toFixed(1) + ' KB';
    }
    return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  }
}

class ListState {
  count: number = 0;
  truncated: boolean = false;
}
