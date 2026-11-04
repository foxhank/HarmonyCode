import { ChatMessage, LlmResult, LlmStreamListener, MessagePart, PartKind, Role, StopReason, TokenUsage }
  from './LlmTypes';
import { StreamEvent, StreamEventKind } from './StreamEvent';

/** Raised when the provider reports an error inside the stream. */
export class StreamError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'StreamError';
  }
}

const GENERATED_ID_PREFIX: string = 'call_';

/**
 * Builds the assistant message from normalized stream events, in the order parts first
 * appeared, and forwards live deltas to an optional listener.
 */
export class ResponseAssembler {
  private parts: MessagePart[] = [];
  private byKey: Map<string, MessagePart> = new Map();
  private usage: TokenUsage = new TokenUsage();
  private stopReason: string = StopReason.END;
  private listener: LlmStreamListener | null;
  private producedOutput: boolean = false;

  constructor(listener: LlmStreamListener | null) {
    this.listener = listener;
  }

  /** True once anything user-visible streamed (retrying then would duplicate output). */
  get hasOutput(): boolean {
    return this.producedOutput;
  }

  accept(events: StreamEvent[]): void {
    for (const e of events) {
      this.one(e);
    }
  }

  result(): LlmResult {
    const parts: MessagePart[] = [];
    let n = 0;
    for (const p of this.parts) {
      if (p.kind === PartKind.TEXT && p.text.length === 0) {
        continue;
      }
      if (p.kind === PartKind.TOOL_CALL) {
        n++;
        if (p.callId.length === 0) {
          p.callId = GENERATED_ID_PREFIX + Date.now().toString(36) + '_' + n;
        }
        if (p.argumentsJson.trim().length === 0) {
          p.argumentsJson = '{}';
        }
      }
      parts.push(p);
    }
    let stop = this.stopReason;
    // Formats disagree on how they flag tool use; the presence of calls is what counts.
    if (stop === StopReason.END && parts.some((p: MessagePart) => p.kind === PartKind.TOOL_CALL)) {
      stop = StopReason.TOOL_CALLS;
    }
    return new LlmResult(new ChatMessage(Role.ASSISTANT, parts), stop, this.usage);
  }

  private part(key: string, kind: string): MessagePart {
    const existing = this.byKey.get(key + '|' + kind);
    if (existing !== undefined) {
      return existing;
    }
    const p = new MessagePart();
    p.kind = kind;
    this.parts.push(p);
    this.byKey.set(key + '|' + kind, p);
    return p;
  }

  private one(e: StreamEvent): void {
    switch (e.kind) {
      case StreamEventKind.TEXT_DELTA:
        if (e.text.length > 0) {
          this.part(e.key, PartKind.TEXT).text += e.text;
          this.producedOutput = true;
          this.listener?.onTextDelta(e.text);
        }
        break;
      case StreamEventKind.REASONING_DELTA:
        this.part(e.key, PartKind.REASONING).text += e.text;
        if (e.text.length > 0) {
          this.producedOutput = true;
          this.listener?.onReasoningDelta(e.text);
        }
        break;
      case StreamEventKind.REASONING_META: {
        const p = this.part(e.key, PartKind.REASONING);
        if (e.signature.length > 0) {
          p.signature = e.signature;
        }
        if (e.callId.length > 0) {
          p.callId = e.callId;
        }
        if (p.text.length === 0 && e.text.length > 0) {
          p.text = e.text;
          this.listener?.onReasoningDelta(e.text);
        }
        break;
      }
      case StreamEventKind.REDACTED_REASONING:
        this.part(e.key, PartKind.REDACTED_REASONING).text += e.text;
        break;
      case StreamEventKind.TOOL_CALL_START: {
        const p = this.part(e.key, PartKind.TOOL_CALL);
        const isNew = p.toolName.length === 0 && p.callId.length === 0;
        if (e.callId.length > 0) {
          p.callId = e.callId;
        }
        if (e.toolName.length > 0) {
          p.toolName = e.toolName;
        }
        this.producedOutput = true;
        if (isNew) {
          this.listener?.onToolCallStart(p.callId, p.toolName);
        }
        break;
      }
      case StreamEventKind.TOOL_CALL_DELTA:
        this.part(e.key, PartKind.TOOL_CALL).argumentsJson += e.text;
        break;
      case StreamEventKind.TOOL_CALL_ARGUMENTS:
        if (e.text.length > 0) {
          this.part(e.key, PartKind.TOOL_CALL).argumentsJson = e.text;
        }
        break;
      case StreamEventKind.USAGE:
        if (e.inputTokens >= 0) {
          this.usage.inputTokens = e.inputTokens;
        }
        if (e.outputTokens >= 0) {
          this.usage.outputTokens = e.outputTokens;
        }
        if (e.cachedTokens >= 0) {
          this.usage.cachedTokens = e.cachedTokens;
        }
        break;
      case StreamEventKind.STOP:
        this.stopReason = e.stopReason;
        break;
      case StreamEventKind.ERROR:
        throw new StreamError(e.text);
      default:
        break;
    }
  }
}
