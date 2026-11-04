import { ToolSpec } from '../../llm/LlmTypes';
import { FsEntry } from '../AgentFs';
import { AgentLimits } from '../AgentLimits';
import { PathGuard } from '../PathGuard';
import { AgentTool, ToolArgs, ToolContext, ToolInputError, ToolKind, ToolLabel, ToolOutput } from '../ToolTypes';
import { GlobPattern } from '../util/GlobPattern';
import { ProjectWalker } from '../util/ProjectWalker';
import { Schema } from './Schema';

/** Finds files by name pattern. */
export class GlobTool implements AgentTool {
  readonly kind: string = ToolKind.READ;
  readonly spec: ToolSpec = {
    name: 'glob',
    description: 'Find files whose path matches a glob pattern, e.g. "**/*.py", "src/**/test_*.ts", ' +
      '"*.{json,yaml}". A pattern without "/" matches file names at any depth. Returns paths relative ' +
      'to the working folder.',
    parameters: Schema.object({
      'pattern': Schema.str('Glob pattern.'),
      'path': Schema.str('Folder to search in. Default: the working folder.')
    }, ['pattern'])
  };

  label(args: ToolArgs): ToolLabel {
    return { verbKey: 'agent_tool_glob', target: args.optStr('pattern', '') };
  }

  async preview(args: ToolArgs, ctx: ToolContext): Promise<string> {
    return '';
  }

  async run(args: ToolArgs, ctx: ToolContext): Promise<ToolOutput> {
    const base = ctx.paths.resolve(args.optStr('path', '.'));
    const st = await ctx.fs.stat(base);
    if (st === null || !st.isDir) {
      throw new ToolInputError('Not a folder: ' + ctx.paths.rel(base));
    }
    const glob = new GlobPattern(args.str('pattern'));
    const hits: string[] = [];
    let more = false;
    const files: FsEntry[] = await ProjectWalker.files(ctx.fs, base, AgentLimits.WALK_MAX_FILES, ctx.cancel);
    for (const f of files) {
      const relToBase = PathGuard.relTo(base, f.path);
      if (glob.matches(relToBase)) {
        if (hits.length >= AgentLimits.GLOB_MAX_RESULTS) {
          more = true;
          break;
        }
        hits.push(ctx.paths.rel(f.path));
      }
    }
    if (hits.length === 0) {
      return ToolOutput.ok('No files match ' + glob.source);
    }
    let text = hits.join('\n');
    if (more) {
      text += `\n[more than ${AgentLimits.GLOB_MAX_RESULTS} matches; use a narrower pattern]`;
    }
    return ToolOutput.ok(text);
  }
}
