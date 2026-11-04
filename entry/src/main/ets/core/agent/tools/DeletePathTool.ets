import { ToolSpec } from '../../llm/LlmTypes';
import { AgentTool, ToolArgs, ToolContext, ToolInputError, ToolKind, ToolLabel, ToolOutput } from '../ToolTypes';
import { Schema } from './Schema';

/** Deletes a file or folder. */
export class DeletePathTool implements AgentTool {
  readonly kind: string = ToolKind.EDIT;
  readonly spec: ToolSpec = {
    name: 'delete_path',
    description: 'Delete a file, or a folder and everything in it. The working folder itself cannot be deleted.',
    parameters: Schema.object({
      'path': Schema.str('File or folder (relative to the working folder, or absolute).')
    }, ['path'])
  };

  label(args: ToolArgs): ToolLabel {
    return { verbKey: 'agent_tool_delete', target: args.optStr('path', '') };
  }

  async preview(args: ToolArgs, ctx: ToolContext): Promise<string> {
    const path = ctx.paths.resolve(args.str('path'));
    const st = await ctx.fs.stat(path);
    return (st !== null && st.isDir ? 'rm -r ' : 'rm ') + ctx.paths.rel(path);
  }

  async run(args: ToolArgs, ctx: ToolContext): Promise<ToolOutput> {
    const path = ctx.paths.resolve(args.str('path'));
    const rel = ctx.paths.rel(path);
    if (path === ctx.paths.root || path === '/') {
      throw new ToolInputError('Refusing to delete the working folder or the file system root.');
    }
    const st = await ctx.fs.stat(path);
    if (st === null) {
      throw new ToolInputError('No such file or folder: ' + rel);
    }
    await ctx.fs.remove(path);
    ctx.reads.forget(path);
    const out = ToolOutput.ok(`Deleted ${st.isDir ? 'folder' : 'file'} ${rel}.`);
    out.changedFiles = [path];
    return out;
  }
}
