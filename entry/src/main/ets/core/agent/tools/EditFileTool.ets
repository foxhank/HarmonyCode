import { ToolSpec } from '../../llm/LlmTypes';
import { AgentTool, ToolArgs, ToolContext, ToolKind, ToolLabel, ToolOutput } from '../ToolTypes';
import { LineDiff } from '../util/LineDiff';
import { EditResult, TextEdit } from '../util/TextEdit';
import { FileGuard } from './FileGuard';
import { Schema } from './Schema';

/** Exact search-and-replace inside one file (the Claude Code / OpenCode edit model). */
export class EditFileTool implements AgentTool {
  readonly kind: string = ToolKind.EDIT;
  readonly spec: ToolSpec = {
    name: 'edit_file',
    description: 'Replace an exact piece of text in a file. old_string must match the file exactly ' +
      '(including indentation and line breaks, without the line-number prefixes read_file shows) and ' +
      'must be unique in the file unless replace_all is true; include surrounding lines to make it ' +
      'unique. You must read the file before editing it. For several changes to one file use multi_edit; ' +
      'to create a file use write_file.',
    parameters: Schema.object({
      'path': Schema.str('File path (relative to the working folder, or absolute).'),
      'old_string': Schema.str('Exact text to replace.'),
      'new_string': Schema.str('Replacement text (must differ from old_string).'),
      'replace_all': Schema.bool('Replace every occurrence instead of exactly one. Default false.')
    }, ['path', 'old_string', 'new_string'])
  };

  label(args: ToolArgs): ToolLabel {
    return { verbKey: 'agent_tool_edit', target: args.optStr('path', '') };
  }

  async preview(args: ToolArgs, ctx: ToolContext): Promise<string> {
    const path = ctx.paths.resolve(args.str('path'));
    const before = await FileGuard.readForEdit(ctx, path);
    return LineDiff.unified(ctx.paths.rel(path), before, this.apply(args, before, ctx.paths.rel(path)).content);
  }

  async run(args: ToolArgs, ctx: ToolContext): Promise<ToolOutput> {
    const path = ctx.paths.resolve(args.str('path'));
    const rel = ctx.paths.rel(path);
    const before = await FileGuard.readForEdit(ctx, path);
    const r = this.apply(args, before, rel);
    await ctx.fs.writeText(path, r.content);
    ctx.reads.record(path, r.content);
    const stats = LineDiff.stats(before, r.content);
    const out = ToolOutput.ok(`Edited ${rel}: ${r.count} replacement${r.count === 1 ? '' : 's'} ` +
      `(+${stats.added} -${stats.removed} lines).`);
    out.display = LineDiff.unified(rel, before, r.content);
    out.changedFiles = [path];
    return out;
  }

  private apply(args: ToolArgs, content: string, rel: string): EditResult {
    return TextEdit.apply(content, args.str('old_string', true), args.str('new_string', true),
      args.optBool('replace_all', false), rel);
  }
}
