import { PathUtil } from '../../fs/PathUtil';
import { ToolSpec } from '../../llm/LlmTypes';
import { AgentTool, ToolArgs, ToolContext, ToolInputError, ToolKind, ToolLabel, ToolOutput } from '../ToolTypes';
import { Schema } from './Schema';

/** Moves or renames a file or folder. */
export class MovePathTool implements AgentTool {
  readonly kind: string = ToolKind.EDIT;
  readonly spec: ToolSpec = {
    name: 'move_path',
    description: 'Move or rename a file or folder. Parent folders of the destination are created. Fails ' +
      'when the destination exists unless overwrite is true (files only).',
    parameters: Schema.object({
      'from': Schema.str('Existing file or folder.'),
      'to': Schema.str('New path.'),
      'overwrite': Schema.bool('Replace an existing destination file. Default false.')
    }, ['from', 'to'])
  };

  label(args: ToolArgs): ToolLabel {
    return { verbKey: 'agent_tool_move', target: args.optStr('from', '') + ' → ' + args.optStr('to', '') };
  }

  async preview(args: ToolArgs, ctx: ToolContext): Promise<string> {
    return 'mv ' + ctx.paths.rel(ctx.paths.resolve(args.str('from'))) + ' ' + ctx.paths.rel(ctx.paths.resolve(args.str('to')));
  }

  async run(args: ToolArgs, ctx: ToolContext): Promise<ToolOutput> {
    const from = ctx.paths.resolve(args.str('from'));
    const to = ctx.paths.resolve(args.str('to'));
    const relFrom = ctx.paths.rel(from);
    const relTo = ctx.paths.rel(to);
    if (from === ctx.paths.root) {
      throw new ToolInputError('Refusing to move the working folder.');
    }
    if (PathUtil.isInside(from, to)) {
      throw new ToolInputError(`Cannot move ${relFrom} into itself.`);
    }
    const src = await ctx.fs.stat(from);
    if (src === null) {
      throw new ToolInputError('No such file or folder: ' + relFrom);
    }
    const dst = await ctx.fs.stat(to);
    if (dst !== null) {
      if (dst.isDir || src.isDir || !args.optBool('overwrite', false)) {
        throw new ToolInputError(`${relTo} already exists.` + (dst.isDir || src.isDir ? '' : ' Set overwrite to replace it.'));
      }
    }
    await ctx.fs.mkdirs(PathUtil.dirName(to));
    await ctx.fs.rename(from, to);
    ctx.reads.forget(from);
    ctx.reads.forget(to);
    const out = ToolOutput.ok(`Moved ${relFrom} to ${relTo}.`);
    out.changedFiles = [from, to];
    return out;
  }
}
