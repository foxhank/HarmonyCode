import { Json } from '../../llm/Json';
import { ToolSpec } from '../../llm/LlmTypes';
import { QuestionOption } from '../Interaction';
import { AgentTool, ToolArgs, ToolContext, ToolInputError, ToolKind, ToolLabel, ToolOutput } from '../ToolTypes';
import { Schema } from './Schema';

const MAX_OPTIONS: number = 6;

/** Asks the user a question and waits for the answer (Claude Code's AskUserQuestion). */
export class AskUserTool implements AgentTool {
  readonly kind: string = ToolKind.META;
  readonly spec: ToolSpec = {
    name: 'ask_user',
    description: 'Ask the user a question and wait for the answer. Use it when you genuinely need their ' +
      'decision: ambiguous requirements, a choice between approaches with real trade-offs, or before ' +
      'something destructive they did not ask for. Offer 2-' + MAX_OPTIONS + ' concrete options when you can ' +
      '(the user may also type their own answer). Do not use it for things you can find out yourself.',
    parameters: Schema.object({
      'question': Schema.str('The question, one or two sentences.'),
      'options': Schema.array('Suggested answers.', Schema.object({
        'label': Schema.str('Short answer (1-5 words).'),
        'description': Schema.str('What choosing it means.')
      }, ['label'])),
      'multi_select': Schema.bool('Allow choosing several options. Default false.')
    }, ['question'])
  };

  label(args: ToolArgs): ToolLabel {
    return { verbKey: 'agent_tool_ask', target: args.optStr('question', '') };
  }

  async preview(args: ToolArgs, ctx: ToolContext): Promise<string> {
    return '';
  }

  async run(args: ToolArgs, ctx: ToolContext): Promise<ToolOutput> {
    const question = args.str('question').trim();
    const options: QuestionOption[] = [];
    for (const o of args.objects('options').slice(0, MAX_OPTIONS)) {
      const label = Json.str(o, 'label').trim();
      if (label.length > 0) {
        options.push({ label: label, description: Json.str(o, 'description').trim() });
      }
    }
    if (question.length === 0) {
      throw new ToolInputError('question must not be empty.');
    }
    const answer = (await ctx.prompter.ask({
      callId: ctx.callId, question: question, options: options, multiSelect: args.optBool('multi_select', false)
    })).trim();
    ctx.cancel.throwIfCancelled();
    if (answer.length === 0) {
      return ToolOutput.ok('The user dismissed the question without answering. Make a reasonable choice yourself ' +
        'and say which one you made, or stop if you cannot proceed.');
    }
    const out = ToolOutput.ok('The user answered: ' + answer);
    out.display = answer;
    return out;
  }
}
