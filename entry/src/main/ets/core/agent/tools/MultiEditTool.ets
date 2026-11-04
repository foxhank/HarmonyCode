import { Json, JsonObject } from '../../llm/Json';
import { ToolSpec } from '../../llm/LlmTypes';
import { AgentTool, ToolArgs, ToolContext, ToolInputError, ToolKind, ToolLabel, ToolOutput } from '../ToolTypes';
import { LineDiff } from '../util/LineDiff';
import { TextEdit } from '../util/TextEdit';
import { FileGuard } from './FileGuard';
import { Schema } from './Schema';

/** Several exact replacements in one file, applied in order and all-or-nothing. */
export class MultiEditTool implements AgentTool {
  readonly kind: string = ToolKind.EDIT;
  readonly spec: ToolSpec = {
    name: 'multi_edit',
    description: 'Make several edits to one file in a single step. Edits apply in order, each to the ' +
      'result of the previous one, with the same rules as edit_file; if any edit fails, none is applied. ' +
      'Prefer this over several edit_file calls on the same file.',
    parameters: Schema.object({
      'path': Schema.str('File path (relative to the working folder, or absolute).'),
      'edits': Schema.array('The edits, in order.', Schema.object({
        'old_string': Schema.str('Exact text to replace.'),
        'new_string': Schema.str('Replacement text.'),
        'replace_all': Schema.bool('Replace every occurrence. Default false.')
      }, ['old_string', 'new_string']))
    }, ['path', 'edits'])
  };

  label(args: ToolArgs): ToolLabel {
    return { verbKey: 'agent_tool_edit', target: args.optStr('path', '') };
  }

  async preview(args: ToolArgs, ctx: ToolContext): Promise<string> {
    const path = ctx.paths.resolve(args.str('path'));
    const before = await FileGuard.readForEdit(ctx, path);
    return LineDiff.unified(ctx.paths.rel(path), before, this.applyAll(args, before, ctx.paths.rel(path)).content);
  }

  async run(args: ToolArgs, ctx: ToolContext): Promise<ToolOutput> {
    const path = ctx.paths.resolve(args.str('path'));
    const rel = ctx.paths.rel(path);
    const before = await FileGuard.readForEdit(ctx, path);
    const r = this.applyAll(args, before, rel);
    await ctx.fs.writeText(path, r.content);
    ctx.reads.record(path, r.content);
    const stats = LineDiff.stats(before, r.content);
    const out = ToolOutput.ok(`Edited ${rel}: ${r.edits} edits, ${r.count} replacements ` +
      `(+${stats.added} -${stats.removed} lines).`);
    out.display = LineDiff.unified(rel, before, r.content);
    out.changedFiles = [path];
    return out;
  }

  private applyAll(args: ToolArgs, content: string, rel: string): MultiResult {
    const edits: JsonObject[] = args.objects('edits');
    if (edits.length === 0) {
      throw new ToolInputError('edits must contain at least one edit.');
    }
    let text = content;
    let count = 0;
    for (let i = 0; i < edits.length; i++) {
      const e = edits[i];
      const oldStr = Json.value(e, 'old_string');
      const newStr = Json.value(e, 'new_string');
      if (typeof oldStr !== 'string' || typeof newStr !== 'string') {
        throw new ToolInputError(`Edit ${i + 1} needs string old_string and new_string.`);
      }
      try {
        const r = TextEdit.apply(text, oldStr as string, newStr as string, Json.bool(e, 'replace_all', false), rel);
        text = r.content;
        count += r.count;
      } catch (err) {
        throw new ToolInputError(`Edit ${i + 1} of ${edits.length} failed (nothing was changed): ` +
          (err as Error).message);
      }
    }
    return { content: text, count: count, edits: edits.length };
  }
}

interface MultiResult {
  content: string;
  count: number;
  edits: number;
}
