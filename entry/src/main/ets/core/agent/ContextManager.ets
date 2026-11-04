import { CancelToken } from '../llm/CancelToken';
import { ChatModel } from '../llm/ChatModel';
import { ChatMessage, LlmRequest, MessagePart, PartKind, Role, ToolSpec } from '../llm/LlmTypes';
import { AgentLimits } from './AgentLimits';

const PRUNED: string = '[Older tool output removed to save context. Re-run the tool if you need it again.]';

const SUMMARY_PROMPT: string = `Your context window is nearly full, so this conversation will be replaced by \
a summary. Write a handoff summary that lets you continue the work seamlessly. Include:
1. The user's requests and goals, quoted where precise wording matters.
2. What has been done so far: files created or changed (with paths) and key decisions.
3. Important facts learned about the codebase (structure, commands that work, conventions, errors seen).
4. The current state and the exact next steps that remain.
Write only the summary, in the user's language, without calling tools.`;

const SUMMARY_HEADER: string = 'This conversation was compacted because it grew too long. Summary of everything ' +
  'so far:\n\n';
const SUMMARY_FOOTER: string = '\n\nContinue the task from here. Re-read any file before editing it.';

/**
 * Keeps the conversation inside the model's context window: first drops old bulky tool
 * output, then asks the model to summarize the conversation (Codex-style compaction).
 */
export class ContextManager {
  /** Rough token count of a request, for when the provider hasn't reported usage yet. */
  static estimateTokens(system: string, messages: ChatMessage[], tools: ToolSpec[]): number {
    let chars = system.length + JSON.stringify(tools).length;
    for (const m of messages) {
      for (const p of m.parts) {
        chars += p.text.length + p.argumentsJson.length + p.toolName.length + 16;
      }
    }
    return Math.ceil(chars / AgentLimits.CHARS_PER_TOKEN);
  }

  static threshold(contextWindow: number): number {
    return Math.floor(contextWindow * AgentLimits.COMPACT_THRESHOLD);
  }

  /**
   * Replaces long tool results outside the last few turns with a stub. Returns true when
   * anything was removed. Pairs of calls and results stay intact, as every format requires.
   */
  static prune(messages: ChatMessage[]): boolean {
    let userTurns = 0;
    let keepFrom = 0;
    for (let i = messages.length - 1; i >= 0; i--) {
      if (ContextManager.isUserText(messages[i])) {
        userTurns++;
        if (userTurns >= AgentLimits.PRUNE_KEEP_TURNS) {
          keepFrom = i;
          break;
        }
      }
    }
    let changed = false;
    for (let i = 0; i < keepFrom; i++) {
      for (const p of messages[i].parts) {
        if (p.kind === PartKind.TOOL_RESULT && p.text.length > AgentLimits.PRUNE_TOOL_OUTPUT_CHARS) {
          p.text = PRUNED;
          changed = true;
        }
      }
    }
    return changed;
  }

  /** Summarizes `messages` with the model and returns the new, single-message history. */
  static async compact(model: ChatModel, system: string, messages: ChatMessage[], cancel: CancelToken): Promise<ChatMessage[]> {
    const req = new LlmRequest();
    req.system = system;
    req.messages = messages.concat([ChatMessage.user(SUMMARY_PROMPT)]);
    const r = await model.complete(req, null, cancel);
    const summary = r.message.textContent().trim();
    if (summary.length === 0) {
      throw new Error('The model returned an empty summary while compacting the conversation.');
    }
    return [new ChatMessage(Role.USER, [MessagePart.text(SUMMARY_HEADER + summary + SUMMARY_FOOTER)])];
  }

  /** A user message typed by the user (not one that only carries tool results). */
  static isUserText(m: ChatMessage): boolean {
    return m.role === Role.USER && m.parts.some((p: MessagePart) => p.kind === PartKind.TEXT);
  }
}
