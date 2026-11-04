import { ToolSpec } from '../../llm/LlmTypes';
import { AgentTool, ToolArgs, ToolContext, ToolInputError, ToolKind, ToolLabel, ToolOutput } from '../ToolTypes';
import { LineDiff } from '../util/LineDiff';
import { TextLimits } from '../util/TextLimits';
import { Schema } from './Schema';

/** Creates a file or replaces one the agent has read. */
export class WriteFileTool implements AgentTool {
  readonly kind: string = ToolKind.EDIT;
  readonly spec: ToolSpec = {
    name: 'write_file',
    description: 'Create a new file, or overwrite an existing one with entirely new content. Parent ' +
      'folders are created. To overwrite an existing file you must have read it first. Prefer ' +
      'edit_file or multi_edit for changing part of a file.',
    parameters: Schema.object({
      'path': Schema.str('File path (relative to the working folder, or absolute).'),
      'content': Schema.str('The complete file content.')
    }, ['path', 'content'])
  };

  label(args: ToolArgs): ToolLabel {
    return { verbKey: 'agent_tool_write', target: args.optStr('path', '') };
  }

  async preview(args: ToolArgs, ctx: ToolContext): Promise<string> {
    const path = ctx.paths.resolve(args.str('path'));
    const st = await ctx.fs.stat(path);
    const before = st !== null && !st.isDir ? await ctx.fs.readText(path) : '';
    return LineDiff.unified(ctx.paths.rel(path), before, args.str('content', true));
  }

  async run(args: ToolArgs, ctx: ToolContext): Promise<ToolOutput> {
    const path = ctx.paths.resolve(args.str('path'));
    const rel = ctx.paths.rel(path);
    const content = args.str('content', true);
    const st = await ctx.fs.stat(path);
    if (st !== null && st.isDir) {
      throw new ToolInputError(rel + ' is a folder.');
    }
    let before = '';
    if (st !== null) {
      before = await ctx.fs.readText(path);
      if (!ctx.reads.hasRead(path)) {
        throw new ToolInputError(`${rel} already exists. Read it with read_file before overwriting it.`);
      }
      if (!ctx.reads.isCurrent(path, before)) {
        throw new ToolInputError(`${rel} changed on disk since you read it. Read it again before writing.`);
      }
    }
    await ctx.fs.writeText(path, content);
    ctx.reads.record(path, content);
    const diff = LineDiff.unified(rel, before, content);
    const stats = LineDiff.stats(before, content);
    const out = ToolOutput.ok(st !== null ?
      `Overwrote ${rel} (+${stats.added} -${stats.removed} lines, now ${TextLimits.countLines(content)} lines).` :
      `Created ${rel} (${TextLimits.countLines(content)} lines).`);
    out.display = diff;
    out.changedFiles = [path];
    return out;
  }
}
