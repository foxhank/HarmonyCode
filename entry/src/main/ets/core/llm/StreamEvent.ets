/** What a decoder saw in the stream. */
export class StreamEventKind {
  static readonly TEXT_DELTA: string = 'text_delta';
  static readonly REASONING_DELTA: string = 'reasoning_delta';
  /** Sets the signature / encrypted content (and provider id) of a reasoning part. */
  static readonly REASONING_META: string = 'reasoning_meta';
  static readonly REDACTED_REASONING: string = 'redacted_reasoning';
  static readonly TOOL_CALL_START: string = 'tool_call_start';
  static readonly TOOL_CALL_DELTA: string = 'tool_call_delta';
  /** Replaces a tool call's arguments with the complete JSON (sent by some formats at the end). */
  static readonly TOOL_CALL_ARGUMENTS: string = 'tool_call_arguments';
  static readonly USAGE: string = 'usage';
  static readonly STOP: string = 'stop';
  static readonly ERROR: string = 'error';
}

/**
 * Normalized stream event. `key` identifies the content part the event belongs to, so deltas
 * of interleaved parts (several tool calls, reasoning then text) land in the right place.
 */
export class StreamEvent {
  kind: string;
  key: string = '';
  text: string = '';
  callId: string = '';
  toolName: string = '';
  signature: string = '';
  inputTokens: number = -1;
  outputTokens: number = -1;
  cachedTokens: number = -1;
  stopReason: string = '';

  constructor(kind: string) {
    this.kind = kind;
  }

  static text(key: string, text: string): StreamEvent {
    const e = new StreamEvent(StreamEventKind.TEXT_DELTA);
    e.key = key;
    e.text = text;
    return e;
  }

  static reasoning(key: string, text: string): StreamEvent {
    const e = new StreamEvent(StreamEventKind.REASONING_DELTA);
    e.key = key;
    e.text = text;
    return e;
  }

  /** `fallbackText` fills the reasoning text only if no deltas streamed for this part. */
  static reasoningMeta(key: string, signature: string, id: string, fallbackText: string = ''): StreamEvent {
    const e = new StreamEvent(StreamEventKind.REASONING_META);
    e.key = key;
    e.signature = signature;
    e.callId = id;
    e.text = fallbackText;
    return e;
  }

  static redacted(key: string, data: string): StreamEvent {
    const e = new StreamEvent(StreamEventKind.REDACTED_REASONING);
    e.key = key;
    e.text = data;
    return e;
  }

  static toolStart(key: string, callId: string, toolName: string): StreamEvent {
    const e = new StreamEvent(StreamEventKind.TOOL_CALL_START);
    e.key = key;
    e.callId = callId;
    e.toolName = toolName;
    return e;
  }

  static toolDelta(key: string, argsDelta: string): StreamEvent {
    const e = new StreamEvent(StreamEventKind.TOOL_CALL_DELTA);
    e.key = key;
    e.text = argsDelta;
    return e;
  }

  static toolArguments(key: string, argsJson: string): StreamEvent {
    const e = new StreamEvent(StreamEventKind.TOOL_CALL_ARGUMENTS);
    e.key = key;
    e.text = argsJson;
    return e;
  }

  /** Pass -1 for counts the event doesn't carry. */
  static usage(input: number, output: number, cached: number): StreamEvent {
    const e = new StreamEvent(StreamEventKind.USAGE);
    e.inputTokens = input;
    e.outputTokens = output;
    e.cachedTokens = cached;
    return e;
  }

  static stop(reason: string): StreamEvent {
    const e = new StreamEvent(StreamEventKind.STOP);
    e.stopReason = reason;
    return e;
  }

  static error(message: string): StreamEvent {
    const e = new StreamEvent(StreamEventKind.ERROR);
    e.text = message;
    return e;
  }
}
