import { TokenUsage } from '../llm/LlmTypes';
import { PlanStep } from './PlanTypes';
import { ToolLabel, ToolOutput } from './ToolTypes';

/** How a turn (one user message and all the steps it caused) ended. */
export class TurnStatus {
  static readonly DONE: string = 'done';
  static readonly CANCELLED: string = 'cancelled';
  static readonly ERROR: string = 'error';
  /** Stopped at the step limit; the user can say "continue". */
  static readonly STEP_LIMIT: string = 'step_limit';
}

/** State of a tool call shown in the transcript. */
export class ToolCallStatus {
  static readonly AWAITING_APPROVAL: string = 'awaiting_approval';
  static readonly RUNNING: string = 'running';
  static readonly DONE: string = 'done';
  static readonly FAILED: string = 'failed';
  static readonly DENIED: string = 'denied';
  static readonly CANCELLED: string = 'cancelled';
}

/** Notices the agent shows inline. */
export class NoticeKind {
  static readonly COMPACTED: string = 'compacted';
  static readonly RETRYING: string = 'retrying';
  static readonly TRUNCATED: string = 'truncated';
}

/** A tool call as the UI sees it. */
export interface ToolCallView {
  callId: string;
  toolName: string;
  kind: string;
  label: ToolLabel;
  argumentsJson: string;
}

/** Everything the agent reports while it works. The UI implements this. */
export interface AgentListener {
  onTurnStart(): void;
  /** A new model call starts (step n of the turn). */
  onStepStart(step: number): void;
  onTextDelta(text: string): void;
  onReasoningDelta(text: string): void;
  onToolCall(call: ToolCallView): void;
  onToolStatus(callId: string, status: string): void;
  onToolOutput(callId: string, output: ToolOutput): void;
  onCommandOutput(callId: string, chunk: string): void;
  onPlan(steps: PlanStep[], explanation: string): void;
  /** `contextTokens`: how much of the context window the conversation now uses. */
  onUsage(usage: TokenUsage, contextTokens: number, contextWindow: number): void;
  onNotice(kind: string, detail: string): void;
  /** Files changed by a tool ('' = unknown, refresh everything). */
  onFilesChanged(paths: string[]): void;
  onTurnEnd(status: string, error: string): void;
}
