import { ToolSpec } from '../../llm/LlmTypes';
import { AgentTool, ToolArgs, ToolContext, ToolInputError, ToolKind, ToolLabel, ToolOutput } from '../ToolTypes';
import { Schema } from './Schema';

/** Delegates a self-contained research task to a sub-agent with a fresh context (Claude Code's Task). */
export class TaskTool implements AgentTool {
  readonly kind: string = ToolKind.META;
  readonly spec: ToolSpec = {
    name: 'task',
    description: 'Start a sub-agent for a self-contained research task: exploring a large codebase, finding ' +
      'where something is implemented, or reading documentation on the web. It has its own context window ' +
      'and read-only tools (list, read, glob, grep, command_output, web search and fetch), works ' +
      'autonomously and returns one report. Use it to keep your own context small. Give it a complete, ' +
      'specific prompt: it cannot see this conversation. It cannot change files or run commands.',
    parameters: Schema.object({
      'description': Schema.str('3-5 words describing the task, shown to the user.'),
      'prompt': Schema.str('Everything the sub-agent needs: the goal, what to look at, and what to report back.')
    }, ['description', 'prompt'])
  };

  label(args: ToolArgs): ToolLabel {
    return { verbKey: 'agent_tool_task', target: args.optStr('description', '') };
  }

  async preview(args: ToolArgs, ctx: ToolContext): Promise<string> {
    return '';
  }

  async run(args: ToolArgs, ctx: ToolContext): Promise<ToolOutput> {
    if (ctx.subagents === null) {
      throw new ToolInputError('Sub-agents cannot start other sub-agents; do the work yourself.');
    }
    const prompt = args.str('prompt');
    const progress: string[] = [];
    const report = await ctx.subagents.runSubagent(prompt, (line: string) => {
      progress.push(line);
      ctx.host.commandOutput(ctx.callId, line + '\n');
    }, ctx.cancel);
    const out = ToolOutput.ok(report.trim().length > 0 ? report : 'The sub-agent finished without a report.');
    out.display = progress.join('\n') + (progress.length > 0 ? '\n\n' : '') + report;
    return out;
  }
}
