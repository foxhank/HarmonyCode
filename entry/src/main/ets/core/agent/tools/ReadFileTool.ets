import { ToolSpec } from '../../llm/LlmTypes';
import { AgentLimits } from '../AgentLimits';
import { AgentTool, ToolArgs, ToolContext, ToolInputError, ToolKind, ToolLabel, ToolOutput } from '../ToolTypes';
import { TextLimits } from '../util/TextLimits';
import { Schema } from './Schema';

const LINE_NO_WIDTH: number = 6;

/** Reads a text file with line numbers, optionally a window of lines. */
export class ReadFileTool implements AgentTool {
  readonly kind: string = ToolKind.READ;
  readonly spec: ToolSpec = {
    name: 'read_file',
    description: 'Read a text file. Output lines are prefixed with their line number and a tab ' +
      '(the prefix is not part of the file). Reads up to ' + AgentLimits.READ_DEFAULT_LINES +
      ' lines by default; use offset/limit for long files. Always read a file before editing it.',
    parameters: Schema.object({
      'path': Schema.str('File path (relative to the working folder, or absolute).'),
      'offset': Schema.int('First line to read (1-based). Default 1.'),
      'limit': Schema.int('Maximum number of lines. Default ' + AgentLimits.READ_DEFAULT_LINES + '.')
    }, ['path'])
  };

  label(args: ToolArgs): ToolLabel {
    return { verbKey: 'agent_tool_read', target: args.optStr('path', '') };
  }

  async preview(args: ToolArgs, ctx: ToolContext): Promise<string> {
    return '';
  }

  async run(args: ToolArgs, ctx: ToolContext): Promise<ToolOutput> {
    const path = ctx.paths.resolve(args.str('path'));
    const rel = ctx.paths.rel(path);
    const st = await ctx.fs.stat(path);
    if (st === null) {
      throw new ToolInputError('File not found: ' + rel);
    }
    if (st.isDir) {
      throw new ToolInputError(rel + ' is a folder; use list_dir.');
    }
    const content = await ctx.fs.readText(path);
    ctx.reads.record(path, content);
    if (content.length === 0) {
      return ToolOutput.ok(`[${rel} is empty]`);
    }
    const lines = content.split('\n');
    if (lines.length > 1 && lines[lines.length - 1] === '') {
      lines.pop();
    }
    const offset = Math.max(1, Math.floor(args.optNum('offset', 1)));
    const limit = Math.max(1, Math.floor(args.optNum('limit', AgentLimits.READ_DEFAULT_LINES)));
    if (offset > lines.length) {
      throw new ToolInputError(`offset ${offset} is past the end of ${rel} (${lines.length} lines).`);
    }
    const end = Math.min(lines.length, offset - 1 + limit);
    const out: string[] = [];
    for (let i = offset - 1; i < end; i++) {
      const no = (i + 1).toString();
      out.push(' '.repeat(Math.max(0, LINE_NO_WIDTH - no.length)) + no + '\t' +
        TextLimits.line(lines[i], AgentLimits.READ_MAX_LINE_CHARS));
    }
    if (end < lines.length || offset > 1) {
      out.push(`\n[showing lines ${offset}-${end} of ${lines.length}]`);
    }
    return ToolOutput.ok(out.join('\n'));
  }
}
