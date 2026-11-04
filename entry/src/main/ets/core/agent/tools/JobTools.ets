import { ToolSpec } from '../../llm/LlmTypes';
import { AgentLimits } from '../AgentLimits';
import { BackgroundJob } from '../BackgroundJobs';
import { AgentTool, ToolArgs, ToolContext, ToolInputError, ToolKind, ToolLabel, ToolOutput } from '../ToolTypes';
import { TextLimits } from '../util/TextLimits';
import { Schema } from './Schema';

function status(j: BackgroundJob): string {
  const secs = Math.round((Date.now() - j.startedAt) / 1000);
  if (!j.done) {
    return `running for ${secs}s`;
  }
  if (j.killed) {
    return 'stopped by kill_command';
  }
  return j.timedOut ? 'timed out' : `exited with code ${j.exitCode}`;
}

function jobList(ctx: ToolContext): string {
  const jobs = ctx.jobs.list();
  if (jobs.length === 0) {
    return 'There are no background jobs.';
  }
  return 'Background jobs:\n' + jobs.map((j: BackgroundJob) => `- ${j.id}: ${status(j)} — ${j.command}`).join('\n');
}

/** Reads new output of a background job, optionally waiting for some. */
export class CommandOutputTool implements AgentTool {
  readonly kind: string = ToolKind.READ;
  readonly spec: ToolSpec = {
    name: 'command_output',
    description: 'Get the output a background job (from run_command with run_in_background) produced since you ' +
      'last checked, and whether it is still running. Without job_id, lists all jobs.',
    parameters: Schema.object({
      'job_id': Schema.str('The job id, e.g. "job1".'),
      'wait_ms': Schema.int('Wait up to this long for new output or exit (max ' + AgentLimits.JOB_WAIT_MAX_MS +
        '). Default 0.')
    }, [])
  };

  label(args: ToolArgs): ToolLabel {
    return { verbKey: 'agent_tool_job_output', target: args.optStr('job_id', '') };
  }

  async preview(args: ToolArgs, ctx: ToolContext): Promise<string> {
    return '';
  }

  async run(args: ToolArgs, ctx: ToolContext): Promise<ToolOutput> {
    const id = args.optStr('job_id', '');
    if (id.length === 0) {
      return ToolOutput.ok(jobList(ctx));
    }
    const job = ctx.jobs.get(id);
    if (job === undefined) {
      throw new ToolInputError(`No background job "${id}". ` + jobList(ctx));
    }
    const wait = Math.max(0, Math.min(AgentLimits.JOB_WAIT_MAX_MS, Math.floor(args.optNum('wait_ms', 0))));
    await job.waitForChange(wait, ctx.cancel);
    const text = TextLimits.stripAnsi(job.takeNew());
    const out = ToolOutput.ok(`Job ${job.id}: ${status(job)}.\n` +
      (text.length > 0 ? TextLimits.middle(text, AgentLimits.MAX_TOOL_OUTPUT_CHARS) : '(no new output)'));
    out.display = text;
    return out;
  }
}

/** Stops a background job and everything it started. */
export class KillCommandTool implements AgentTool {
  readonly kind: string = ToolKind.EXECUTE;
  readonly spec: ToolSpec = {
    name: 'kill_command',
    description: 'Stop a background job started with run_command (run_in_background).',
    parameters: Schema.object({
      'job_id': Schema.str('The job id, e.g. "job1".')
    }, ['job_id'])
  };

  label(args: ToolArgs): ToolLabel {
    return { verbKey: 'agent_tool_job_kill', target: args.optStr('job_id', '') };
  }

  async preview(args: ToolArgs, ctx: ToolContext): Promise<string> {
    const job = ctx.jobs.get(args.str('job_id'));
    return 'kill ' + args.str('job_id') + (job !== undefined ? ' (' + job.command + ')' : '');
  }

  async run(args: ToolArgs, ctx: ToolContext): Promise<ToolOutput> {
    const id = args.str('job_id');
    const job = ctx.jobs.get(id);
    if (job === undefined) {
      throw new ToolInputError(`No background job "${id}". ` + jobList(ctx));
    }
    if (!ctx.jobs.kill(id)) {
      return ToolOutput.ok(`Job ${id} had already finished (${status(job)}).`);
    }
    await job.waitForChange(AgentLimits.JOB_KILL_WAIT_MS, ctx.cancel);
    const tail = TextLimits.stripAnsi(job.takeNew());
    return ToolOutput.ok(`Stopped job ${id}.` + (tail.trim().length > 0 ? '\nLast output:\n' +
      TextLimits.middle(tail, AgentLimits.MAX_TOOL_OUTPUT_CHARS) : ''));
  }
}
