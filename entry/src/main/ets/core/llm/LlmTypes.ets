import { JsonObject } from './Json';

/** Who wrote a message. Tool results travel in USER messages, as the Anthropic format does. */
export class Role {
  static readonly USER: string = 'user';
  static readonly ASSISTANT: string = 'assistant';
}

/** Kinds of message content. */
export class PartKind {
  static readonly TEXT: string = 'text';
  /** Model reasoning ("thinking"). Echoed back when a provider requires it. */
  static readonly REASONING: string = 'reasoning';
  /** Reasoning a provider returned in encrypted form only (Anthropic redacted_thinking). */
  static readonly REDACTED_REASONING: string = 'redacted_reasoning';
  static readonly TOOL_CALL: string = 'tool_call';
  static readonly TOOL_RESULT: string = 'tool_result';
}

/**
 * One piece of a message. A single class (rather than a union) keeps it easy to store as JSON
 * and to build in ArkTS; unused fields stay empty.
 */
export class MessagePart {
  kind: string = PartKind.TEXT;
  /** TEXT and REASONING: the text. TOOL_RESULT: the tool output. REDACTED_REASONING: opaque data. */
  text: string = '';
  /** TOOL_CALL / TOOL_RESULT: id pairing a result with its call. REASONING: provider item id. */
  callId: string = '';
  /** TOOL_CALL: tool name. */
  toolName: string = '';
  /** TOOL_CALL: arguments as a JSON object string. */
  argumentsJson: string = '';
  /** TOOL_RESULT: the tool failed. */
  isError: boolean = false;
  /** REASONING: signature (Anthropic) or encrypted content (OpenAI Responses). */
  signature: string = '';

  static text(text: string): MessagePart {
    const p = new MessagePart();
    p.kind = PartKind.TEXT;
    p.text = text;
    return p;
  }

  static reasoning(text: string, signature: string, id: string): MessagePart {
    const p = new MessagePart();
    p.kind = PartKind.REASONING;
    p.text = text;
    p.signature = signature;
    p.callId = id;
    return p;
  }

  static redactedReasoning(data: string): MessagePart {
    const p = new MessagePart();
    p.kind = PartKind.REDACTED_REASONING;
    p.text = data;
    return p;
  }

  static toolCall(callId: string, toolName: string, argumentsJson: string): MessagePart {
    const p = new MessagePart();
    p.kind = PartKind.TOOL_CALL;
    p.callId = callId;
    p.toolName = toolName;
    p.argumentsJson = argumentsJson;
    return p;
  }

  static toolResult(callId: string, output: string, isError: boolean): MessagePart {
    const p = new MessagePart();
    p.kind = PartKind.TOOL_RESULT;
    p.callId = callId;
    p.text = output;
    p.isError = isError;
    return p;
  }
}

/** A message in a provider-neutral conversation. */
export class ChatMessage {
  role: string;
  parts: MessagePart[];

  constructor(role: string, parts: MessagePart[]) {
    this.role = role;
    this.parts = parts;
  }

  static user(text: string): ChatMessage {
    return new ChatMessage(Role.USER, [MessagePart.text(text)]);
  }

  static assistant(text: string): ChatMessage {
    return new ChatMessage(Role.ASSISTANT, [MessagePart.text(text)]);
  }

  /** Concatenated TEXT parts. */
  textContent(): string {
    let out = '';
    for (const p of this.parts) {
      if (p.kind === PartKind.TEXT) {
        out += p.text;
      }
    }
    return out;
  }

  toolCalls(): MessagePart[] {
    return this.parts.filter((p: MessagePart) => p.kind === PartKind.TOOL_CALL);
  }

  /** Rebuilds a message from its JSON form (as written by JSON.stringify). */
  static fromJson(o: ChatMessage): ChatMessage {
    const parts: MessagePart[] = [];
    for (const raw of o.parts) {
      const p = new MessagePart();
      p.kind = raw.kind;
      p.text = raw.text;
      p.callId = raw.callId;
      p.toolName = raw.toolName;
      p.argumentsJson = raw.argumentsJson;
      p.isError = raw.isError;
      p.signature = raw.signature;
      parts.push(p);
    }
    return new ChatMessage(o.role, parts);
  }
}

/** A function the model may call. `parameters` is a JSON Schema object. */
export interface ToolSpec {
  name: string;
  description: string;
  parameters: JsonObject;
}

/** Everything one model call needs, independent of the provider's wire format. */
export class LlmRequest {
  system: string = '';
  messages: ChatMessage[] = [];
  tools: ToolSpec[] = [];
  /** 0 = provider default (Anthropic, which requires a value, gets LlmDefaults.MAX_OUTPUT_TOKENS). */
  maxOutputTokens: number = 0;
  /** NaN = provider default. */
  temperature: number = NaN;
}

/** Why the model stopped. */
export class StopReason {
  static readonly END: string = 'end';
  static readonly TOOL_CALLS: string = 'tool_calls';
  static readonly MAX_TOKENS: string = 'max_tokens';
  static readonly REFUSAL: string = 'refusal';
  static readonly OTHER: string = 'other';
}

export class TokenUsage {
  inputTokens: number = 0;
  outputTokens: number = 0;
  /** Input tokens served from the provider's prompt cache. */
  cachedTokens: number = 0;
}

/** The assembled answer of one model call. */
export class LlmResult {
  message: ChatMessage;
  stopReason: string;
  usage: TokenUsage;

  constructor(message: ChatMessage, stopReason: string, usage: TokenUsage) {
    this.message = message;
    this.stopReason = stopReason;
    this.usage = usage;
  }
}

/** Live progress of a streaming call, for UIs. Every method is optional to act on. */
export interface LlmStreamListener {
  onTextDelta(text: string): void;
  onReasoningDelta(text: string): void;
  /** A tool call began (its arguments are still streaming). */
  onToolCallStart(callId: string, toolName: string): void;
}

export class LlmDefaults {
  static readonly MAX_OUTPUT_TOKENS: number = 8192;
  static readonly REQUEST_TIMEOUT_MS: number = 300000;
  static readonly CONNECT_TIMEOUT_MS: number = 30000;
  static readonly MAX_RETRIES: number = 3;
  static readonly RETRY_BASE_DELAY_MS: number = 1000;
  static readonly RETRY_MAX_DELAY_MS: number = 20000;
}
