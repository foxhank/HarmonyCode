import { ToolSpec } from '../../llm/LlmTypes';
import { FsEntry } from '../AgentFs';
import { AgentLimits } from '../AgentLimits';
import { PathGuard } from '../PathGuard';
import { AgentTool, ToolArgs, ToolContext, ToolInputError, ToolKind, ToolLabel, ToolOutput } from '../ToolTypes';
import { GlobPattern } from '../util/GlobPattern';
import { ProjectWalker } from '../util/ProjectWalker';
import { TextLimits } from '../util/TextLimits';
import { Schema } from './Schema';

const MODE_CONTENT: string = 'content';
const MODE_FILES: string = 'files_with_matches';
const MODE_COUNT: string = 'count';
const MAX_MATCH_LINE: number = 400;

/** Regular-expression search across project files (ripgrep-like output). */
export class GrepTool implements AgentTool {
  readonly kind: string = ToolKind.READ;
  readonly spec: ToolSpec = {
    name: 'grep',
    description: 'Search file contents with a JavaScript regular expression. Output modes: "content" ' +
      '(matching lines as path:line:text, the default), "files_with_matches" (paths only) or "count". ' +
      'Binary files and dependency/build folders are skipped.',
    parameters: Schema.object({
      'pattern': Schema.str('Regular expression, e.g. "def \\\\w+\\\\(" or "TODO|FIXME".'),
      'path': Schema.str('File or folder to search. Default: the working folder.'),
      'include': Schema.str('Only search files matching this glob, e.g. "*.py" or "src/**/*.{ts,tsx}".'),
      'case_insensitive': Schema.bool('Ignore case. Default false.'),
      'output_mode': Schema.enumStr('What to return. Default "content".', [MODE_CONTENT, MODE_FILES, MODE_COUNT]),
      'context': Schema.int('Lines of context before and after each match (content mode, max ' +
        AgentLimits.GREP_MAX_CONTEXT + '). Default 0.')
    }, ['pattern'])
  };

  label(args: ToolArgs): ToolLabel {
    return { verbKey: 'agent_tool_grep', target: args.optStr('pattern', '') };
  }

  async preview(args: ToolArgs, ctx: ToolContext): Promise<string> {
    return '';
  }

  async run(args: ToolArgs, ctx: ToolContext): Promise<ToolOutput> {
    const pattern = args.str('pattern');
    let re: RegExp;
    try {
      re = new RegExp(pattern, args.optBool('case_insensitive', false) ? 'i' : '');
    } catch (e) {
      throw new ToolInputError('Invalid regular expression: ' + (e as Error).message);
    }
    const target = ctx.paths.resolve(args.optStr('path', '.'));
    const st = await ctx.fs.stat(target);
    if (st === null) {
      throw new ToolInputError('No such path: ' + ctx.paths.rel(target));
    }
    const mode = args.optStr('output_mode', MODE_CONTENT);
    const context = Math.max(0, Math.min(AgentLimits.GREP_MAX_CONTEXT, Math.floor(args.optNum('context', 0))));
    const include = args.optStr('include', '');
    const glob = include.length > 0 ? new GlobPattern(include) : null;
    const entries: FsEntry[] = st.isDir ?
      await ProjectWalker.files(ctx.fs, target, AgentLimits.WALK_MAX_FILES, ctx.cancel) :
      [{ name: '', path: target, isDir: false, size: st.size }];

    const out: string[] = [];
    let matches = 0;
    let truncated = false;
    for (const entry of entries) {
      ctx.cancel.throwIfCancelled();
      const f = entry.path;
      const rel = ctx.paths.rel(f);
      if (glob !== null && !glob.matches(st.isDir ? PathGuard.relTo(target, f) : rel)) {
        continue;
      }
      if (entry.size > AgentLimits.GREP_MAX_FILE_BYTES) {
        continue;
      }
      let text = '';
      try {
        text = await ctx.fs.readText(f);
      } catch (e) {
        continue; // binary or unreadable
      }
      const lines = text.split('\n');
      let fileMatches = 0;
      let lastPrinted = -1;
      for (let i = 0; i < lines.length; i++) {
        if (!re.test(lines[i])) {
          continue;
        }
        fileMatches++;
        matches++;
        if (mode === MODE_CONTENT) {
          const from = Math.max(lastPrinted + 1, i - context);
          const to = Math.min(lines.length - 1, i + context);
          if (context > 0 && lastPrinted >= 0 && from > lastPrinted + 1) {
            out.push('--');
          }
          for (let k = from; k <= to; k++) {
            out.push(rel + (k === i ? ':' : '-') + (k + 1) + (k === i ? ':' : '-') +
              TextLimits.line(lines[k].replace(new RegExp('\\r$'), ''), MAX_MATCH_LINE));
          }
          lastPrinted = to;
        }
        if (matches >= AgentLimits.GREP_MAX_MATCHES) {
          truncated = true;
          break;
        }
      }
      if (fileMatches > 0 && mode === MODE_FILES) {
        out.push(rel);
      } else if (fileMatches > 0 && mode === MODE_COUNT) {
        out.push(rel + ':' + fileMatches);
      }
      if (truncated) {
        break;
      }
    }
    if (matches === 0) {
      return ToolOutput.ok('No matches for /' + pattern + '/');
    }
    if (truncated) {
      out.push(`[stopped after ${AgentLimits.GREP_MAX_MATCHES} matches; narrow the pattern or path]`);
    }
    return ToolOutput.ok(out.join('\n'));
  }
}
