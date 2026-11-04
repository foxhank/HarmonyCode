import { ToolCallStatus } from '../../core/agent/AgentEvents';
import { QuestionOption } from '../../core/agent/Interaction';

/** Kinds of entries in the agent transcript. */
export class ItemKind {
  static readonly USER: string = 'user';
  static readonly ASSISTANT: string = 'assistant';
  static readonly REASONING: string = 'reasoning';
  static readonly TOOL: string = 'tool';
  static readonly NOTICE: string = 'notice';
  static readonly ERROR: string = 'error';
}

/** Saved form of an item. */
export interface TranscriptItemJson {
  id: number;
  kind: string;
  text: string;
  callId: string;
  toolName: string;
  toolKind: string;
  verbKey: string;
  target: string;
  status: string;
  output: string;
  display: string;
  isError: boolean;
}

/** One entry in the agent panel: a message, a tool call or a notice. */
@ObservedV2
export class TranscriptItem {
  id: number;
  kind: string;
  /** Message text, reasoning, or notice/error detail. A notice's text is a string-resource name. */
  @Trace text: string = '';
  // Tool calls
  callId: string = '';
  toolName: string = '';
  toolKind: string = '';
  verbKey: string = '';
  target: string = '';
  @Trace status: string = '';
  /** What the model saw. */
  @Trace output: string = '';
  /** Diff or full command output. */
  @Trace display: string = '';
  @Trace isError: boolean = false;
  /** Command output while it runs. */
  @Trace live: string = '';
  /** Approval preview (diff or command line). */
  @Trace preview: string = '';
  /** For command approvals: the prefix "always allow" covers ('' = all commands). */
  @Trace ruleKey: string = '';
  /** ask_user: the question waiting for an answer (cleared once answered). */
  @Trace question: string = '';
  @Trace options: QuestionOption[] = [];
  @Trace multiSelect: boolean = false;
  /** A user message typed while the agent was working. */
  @Trace queued: boolean = false;
  @Trace expanded: boolean = false;
  /** Still streaming. */
  @Trace streaming: boolean = false;

  constructor(id: number, kind: string) {
    this.id = id;
    this.kind = kind;
  }

  get awaitingApproval(): boolean {
    return this.status === ToolCallStatus.AWAITING_APPROVAL;
  }

  get running(): boolean {
    return this.status === ToolCallStatus.RUNNING;
  }

  get awaitingAnswer(): boolean {
    return this.question.length > 0;
  }

  toJson(): TranscriptItemJson {
    return {
      id: this.id, kind: this.kind, text: this.text, callId: this.callId, toolName: this.toolName,
      toolKind: this.toolKind, verbKey: this.verbKey, target: this.target, status: this.status,
      output: this.output, display: this.display, isError: this.isError
    };
  }

  static fromJson(j: TranscriptItemJson): TranscriptItem {
    const t = new TranscriptItem(j.id, j.kind);
    t.text = j.text;
    t.callId = j.callId;
    t.toolName = j.toolName;
    t.toolKind = j.toolKind;
    t.verbKey = j.verbKey;
    t.target = j.target;
    // A call that was interrupted by closing the app is no longer running.
    t.status = j.status === ToolCallStatus.RUNNING || j.status === ToolCallStatus.AWAITING_APPROVAL ?
      ToolCallStatus.CANCELLED : j.status;
    t.output = j.output;
    t.display = j.display;
    t.isError = j.isError;
    return t;
  }
}
