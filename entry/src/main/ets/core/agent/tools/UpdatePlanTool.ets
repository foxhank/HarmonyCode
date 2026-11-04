import { ToolSpec } from '../../llm/LlmTypes';
import { PlanStep, StepStatus } from '../PlanTypes';
import { AgentTool, ToolArgs, ToolContext, ToolInputError, ToolKind, ToolLabel, ToolOutput } from '../ToolTypes';
import { Schema } from './Schema';

/** Keeps a visible task plan (Codex's update_plan / Claude Code's todo list). */
export class UpdatePlanTool implements AgentTool {
  readonly kind: string = ToolKind.META;
  readonly spec: ToolSpec = {
    name: 'update_plan',
    description: 'Create or update the task plan shown to the user. Use it for work with 3 or more ' +
      'steps. Send the whole list each time. Keep exactly one step in_progress while working; mark ' +
      'steps completed as soon as they are done.',
    parameters: Schema.object({
      'explanation': Schema.str('Optional short note about what changed in the plan.'),
      'plan': Schema.array('The complete list of steps, in order.', Schema.object({
        'step': Schema.str('Short description of the step.'),
        'status': Schema.enumStr('Step status.', [StepStatus.PENDING, StepStatus.IN_PROGRESS, StepStatus.COMPLETED])
      }, ['step', 'status']))
    }, ['plan'])
  };

  label(args: ToolArgs): ToolLabel {
    return { verbKey: 'agent_tool_plan', target: '' };
  }

  async preview(args: ToolArgs, ctx: ToolContext): Promise<string> {
    return '';
  }

  async run(args: ToolArgs, ctx: ToolContext): Promise<ToolOutput> {
    const steps: PlanStep[] = [];
    for (const o of args.objects('plan')) {
      const text = typeof o['step'] === 'string' ? (o['step'] as string).trim() : '';
      if (text.length > 0) {
        steps.push({ step: text, status: StepStatus.normalize(typeof o['status'] === 'string' ? o['status'] as string : '') });
      }
    }
    if (steps.length === 0) {
      throw new ToolInputError('plan must contain at least one step with a "step" text.');
    }
    const inProgress = steps.filter((s: PlanStep) => s.status === StepStatus.IN_PROGRESS).length;
    ctx.host.planUpdated(steps, args.optStr('explanation', ''));
    const done = steps.filter((s: PlanStep) => s.status === StepStatus.COMPLETED).length;
    let text = `Plan updated: ${done}/${steps.length} steps completed.`;
    if (inProgress > 1) {
      text += ' Note: keep only one step in_progress at a time.';
    }
    return ToolOutput.ok(text);
  }
}
