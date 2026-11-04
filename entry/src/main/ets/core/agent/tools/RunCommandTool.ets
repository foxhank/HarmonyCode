import { ToolSpec } from '../../llm/LlmTypes';
import { AgentLimits } from '../AgentLimits';
import { AgentTool, ToolArgs, ToolContext, ToolKind, ToolLabel, ToolOutput } from '../ToolTypes';
import { TextLimits } from '../util/TextLimits';
import { Schema } from './Schema';

/** Runs a shell command (project VM / built-in shell, or the remote machine), in the foreground or background. */
export class RunCommandTool implements AgentTool {
  readonly kind: string = ToolKind.EXECUTE;
  readonly spec: ToolSpec = {
    name: 'run_command',
    description: 'Run a shell command and return its exit code and combined stdout/stderr. Use it to ' +
      'build, run tests, run scripts, use git, or install packages. Commands are non-interactive (no ' +
      'stdin): pass flags such as -y. Prefer read_file/grep/glob/list_dir over cat/grep/find for ' +
      'reading and searching. For servers, watchers and other long-running processes set ' +
      'run_in_background: you get a job id right away; check on it with command_output and stop it ' +
      'with kill_command.',
    parameters: Schema.object({
      'command': Schema.str('The command line.'),
      'workdir': Schema.str('Working folder (relative to the working folder, or absolute). Default: the working folder.'),
      'timeout_ms': Schema.int('Timeout in milliseconds for foreground commands (max ' +
        AgentLimits.COMMAND_TIMEOUT_MAX_MS + '). Default ' + AgentLimits.COMMAND_TIMEOUT_DEFAULT_MS + '.'),
      'run_in_background': Schema.bool('Start the command and return immediately with a job id. Default false.'),
      'description': Schema.str('A few words on what the command does, shown to the user.')
    }, ['command'])
  };

  label(args: ToolArgs): ToolLabel {
    return { verbKey: args.optBool('run_in_background', false) ? 'agent_tool_run_bg' : 'agent_tool_run',
      target: args.optStr('command', '') };
  }

  async preview(args: ToolArgs, ctx: ToolContext): Promise<string> {
    const dir = args.optStr('workdir', '');
    return (dir.length > 0 ? '(' + dir + ') ' : '') + '$ ' + args.str('command') +
      (args.optBool('run_in_background', false) ? ' &' : '');
  }

  async run(args: ToolArgs, ctx: ToolContext): Promise<ToolOutput> {
    const command = args.str('command');
    const cwd = ctx.paths.resolve(args.optStr('workdir', '.'));
    if (args.optBool('run_in_background', false)) {
      const job = ctx.jobs.start(ctx.shell, command, cwd, AgentLimits.BACKGROUND_TIMEOUT_MS);
      // Give fast failures (typos, missing tools) a moment to show up.
      await job.waitForChange(AgentLimits.BACKGROUND_FIRST_LOOK_MS, ctx.cancel);
      const early = TextLimits.stripAnsi(job.takeNew());
      const state = job.done ? `It already exited with code ${job.exitCode}.` : 'It is running.';
      const out = ToolOutput.ok(`Started background job ${job.id}. ${state}` +
        (early.trim().length > 0 ? '\nFirst output:\n' + TextLimits.middle(early, AgentLimits.MAX_TOOL_OUTPUT_CHARS) : '') +
        `\nUse command_output with job_id "${job.id}" to see more, kill_command to stop it.`);
      out.display = early;
      out.changedFiles = [''];
      return out;
    }
    const timeout = Math.max(1000, Math.min(AgentLimits.COMMAND_TIMEOUT_MAX_MS,
      Math.floor(args.optNum('timeout_ms', AgentLimits.COMMAND_TIMEOUT_DEFAULT_MS))));
    const r = await ctx.shell.run(command, cwd, timeout, ctx.cancel,
      (chunk: string) => ctx.host.commandOutput(ctx.callId, chunk));
    const output = TextLimits.stripAnsi(r.output);
    const status = r.timedOut ? `Timed out after ${timeout} ms (consider run_in_background).` : `Exit code ${r.exitCode}.`;
    const body = output.trim().length > 0 ? TextLimits.middle(output, AgentLimits.MAX_TOOL_OUTPUT_CHARS) : '(no output)';
    const result = new ToolOutput(status + '\n' + body, r.timedOut || r.exitCode !== 0);
    result.display = output;
    // A command may change any file; '' asks the IDE to refresh everything.
    result.changedFiles = [''];
    return result;
  }
}
