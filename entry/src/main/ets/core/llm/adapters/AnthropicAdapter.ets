import { ApiAdapter, StreamDecoder } from '../ApiAdapter';
import { HttpRequestSpec } from '../HttpTransport';
import { Json, JsonObject } from '../Json';
import { ChatMessage, LlmDefaults, LlmRequest, MessagePart, PartKind, Role, StopReason, ToolSpec } from '../LlmTypes';
import { ApiFormat, endpointUrl, ModelInfo, ProviderConfig } from '../ProviderConfig';
import { StreamEvent } from '../StreamEvent';
import { AdapterSupport } from './AdapterSupport';

const API_VERSION: string = '2023-06-01';
const BLOCK: string = 'b';
/** Anthropic rejects empty text blocks; used where a message would otherwise be empty. */
const EMPTY_TEXT: string = '(empty)';

/**
 * Anthropic Messages API (`POST /v1/messages`), also offered by DeepSeek, Kimi, GLM and other
 * "Anthropic-compatible" endpoints. Tool results ride in user messages as tool_result blocks.
 */
export class AnthropicAdapter implements ApiAdapter {
  readonly format: string = ApiFormat.ANTHROPIC;

  buildRequest(provider: ProviderConfig, model: ModelInfo, request: LlmRequest): HttpRequestSpec {
    let maxTokens = request.maxOutputTokens > 0 ? request.maxOutputTokens : model.maxOutputTokens;
    if (maxTokens <= 0) {
      maxTokens = LlmDefaults.MAX_OUTPUT_TOKENS;
    }
    const body: JsonObject = {
      'model': model.id,
      'max_tokens': maxTokens,
      'messages': AnthropicAdapter.messages(request.messages),
      'stream': true
    };
    if (request.system.length > 0) {
      body['system'] = request.system;
    }
    if (request.tools.length > 0) {
      body['tools'] = request.tools.map((t: ToolSpec): Object => AnthropicAdapter.tool(t));
    }
    if (!Number.isNaN(request.temperature)) {
      body['temperature'] = request.temperature;
    }
    const auth: Record<string, string> = { 'anthropic-version': API_VERSION };
    if (provider.apiKey.length > 0) {
      auth['x-api-key'] = provider.apiKey;
    }
    const path = provider.baseUrl.trim().replace(new RegExp('/+$'), '').endsWith('/v1') ? '/messages' : '/v1/messages';
    return AdapterSupport.spec(provider, endpointUrl(provider.baseUrl, path), auth, body);
  }

  newDecoder(): StreamDecoder {
    return new AnthropicDecoder();
  }

  errorMessage(status: number, body: string): string {
    return AdapterSupport.errorMessage(status, body);
  }

  private static tool(t: ToolSpec): JsonObject {
    const o: JsonObject = { 'name': t.name, 'description': t.description, 'input_schema': t.parameters };
    return o;
  }

  /** Converts messages, merging neighbours with the same role (the API requires alternation). */
  private static messages(messages: ChatMessage[]): Object[] {
    const out: JsonObject[] = [];
    let lastRole = '';
    let blocks: Object[] = [];
    const flush = (): void => {
      if (lastRole.length === 0) {
        return;
      }
      if (blocks.length === 0) {
        blocks.push(AnthropicAdapter.textBlock(EMPTY_TEXT));
      }
      const m: JsonObject = { 'role': lastRole, 'content': blocks };
      out.push(m);
    };
    for (const m of messages) {
      const role = m.role === Role.ASSISTANT ? Role.ASSISTANT : Role.USER;
      if (role !== lastRole) {
        flush();
        lastRole = role;
        blocks = [];
      }
      // Tool results must come before any text in a user message.
      const results: Object[] = [];
      const others: Object[] = [];
      for (const p of m.parts) {
        const b = AnthropicAdapter.block(p);
        if (b === null) {
          continue;
        }
        if (p.kind === PartKind.TOOL_RESULT) {
          results.push(b);
        } else {
          others.push(b);
        }
      }
      blocks = results.concat(blocks).concat(others);
    }
    flush();
    return out;
  }

  private static textBlock(text: string): JsonObject {
    const o: JsonObject = { 'type': 'text', 'text': text };
    return o;
  }

  private static block(p: MessagePart): JsonObject | null {
    if (p.kind === PartKind.TEXT) {
      return p.text.length > 0 ? AnthropicAdapter.textBlock(p.text) : null;
    }
    if (p.kind === PartKind.REASONING) {
      // Thinking can only be replayed with the signature Anthropic issued for it.
      if (p.signature.length === 0) {
        return null;
      }
      const o: JsonObject = { 'type': 'thinking', 'thinking': p.text, 'signature': p.signature };
      return o;
    }
    if (p.kind === PartKind.REDACTED_REASONING) {
      const o: JsonObject = { 'type': 'redacted_thinking', 'data': p.text };
      return o;
    }
    if (p.kind === PartKind.TOOL_CALL) {
      const o: JsonObject = {
        'type': 'tool_use', 'id': p.callId, 'name': p.toolName,
        'input': AdapterSupport.argumentsObject(p.argumentsJson)
      };
      return o;
    }
    if (p.kind === PartKind.TOOL_RESULT) {
      const o: JsonObject = {
        'type': 'tool_result', 'tool_use_id': p.callId,
        'content': p.text.length > 0 ? p.text : EMPTY_TEXT, 'is_error': p.isError
      };
      return o;
    }
    return null;
  }
}

class AnthropicDecoder implements StreamDecoder {
  private stopReason: string = '';
  private sawToolUse: boolean = false;

  onSse(event: string, data: string): StreamEvent[] {
    const o = Json.parseObject(data);
    if (o === null) {
      return [];
    }
    const type = Json.str(o, 'type', event);
    const out: StreamEvent[] = [];
    switch (type) {
      case 'message_start':
        this.usage(Json.obj(Json.obj(o, 'message'), 'usage'), out);
        break;
      case 'content_block_start':
        this.blockStart(BLOCK + Json.num(o, 'index'), Json.obj(o, 'content_block'), out, false);
        break;
      case 'content_block_delta':
        this.blockDelta(BLOCK + Json.num(o, 'index'), Json.obj(o, 'delta'), out);
        break;
      case 'message_delta': {
        const sr = Json.str(Json.obj(o, 'delta'), 'stop_reason');
        if (sr.length > 0) {
          this.stopReason = sr;
        }
        this.usage(Json.obj(o, 'usage'), out);
        break;
      }
      case 'error': {
        const err = Json.obj(o, 'error');
        out.push(StreamEvent.error(Json.str(err, 'type', 'error') + ': ' + Json.str(err, 'message', data)));
        break;
      }
      default:
        break; // ping, content_block_stop, message_stop
    }
    return out;
  }

  onBody(body: JsonObject): StreamEvent[] {
    const out: StreamEvent[] = [];
    if (Json.str(body, 'type') === 'error') {
      const err = Json.obj(body, 'error');
      out.push(StreamEvent.error(Json.str(err, 'message', JSON.stringify(body))));
      return out;
    }
    const blocks = Json.objects(body, 'content');
    for (let i = 0; i < blocks.length; i++) {
      this.blockStart(BLOCK + i, blocks[i], out, true);
    }
    const sr = Json.str(body, 'stop_reason');
    if (sr.length > 0) {
      this.stopReason = sr;
    }
    this.usage(Json.obj(body, 'usage'), out);
    return out;
  }

  finish(): StreamEvent[] {
    return [StreamEvent.stop(this.mapStop())];
  }

  /** `whole`: the block is complete (non-streamed body), so its full content is emitted too. */
  private blockStart(key: string, b: JsonObject | null, out: StreamEvent[], whole: boolean): void {
    const type = Json.str(b, 'type');
    if (type === 'text') {
      const t = Json.str(b, 'text');
      if (t.length > 0) {
        out.push(StreamEvent.text(key, t));
      }
    } else if (type === 'thinking') {
      const t = Json.str(b, 'thinking');
      out.push(StreamEvent.reasoning(key, t));
      const sig = Json.str(b, 'signature');
      if (sig.length > 0) {
        out.push(StreamEvent.reasoningMeta(key, sig, ''));
      }
    } else if (type === 'redacted_thinking') {
      out.push(StreamEvent.redacted(key, Json.str(b, 'data')));
    } else if (type === 'tool_use' || type === 'server_tool_use') {
      this.sawToolUse = true;
      out.push(StreamEvent.toolStart(key, Json.str(b, 'id'), Json.str(b, 'name')));
      const input = Json.obj(b, 'input');
      // Streamed blocks start with an empty input that input_json_delta fills in.
      if (input !== null && (whole || Object.keys(input).length > 0)) {
        out.push(StreamEvent.toolArguments(key, JSON.stringify(input)));
      }
    }
  }

  private blockDelta(key: string, d: JsonObject | null, out: StreamEvent[]): void {
    const type = Json.str(d, 'type');
    if (type === 'text_delta') {
      out.push(StreamEvent.text(key, Json.str(d, 'text')));
    } else if (type === 'input_json_delta') {
      out.push(StreamEvent.toolDelta(key, Json.str(d, 'partial_json')));
    } else if (type === 'thinking_delta') {
      out.push(StreamEvent.reasoning(key, Json.str(d, 'thinking')));
    } else if (type === 'signature_delta') {
      out.push(StreamEvent.reasoningMeta(key, Json.str(d, 'signature'), ''));
    }
  }

  private usage(u: JsonObject | null, out: StreamEvent[]): void {
    if (u === null) {
      return;
    }
    const cacheRead = Json.num(u, 'cache_read_input_tokens');
    const input = Json.has(u, 'input_tokens') ?
      Json.num(u, 'input_tokens') + cacheRead + Json.num(u, 'cache_creation_input_tokens') : -1;
    const output = Json.has(u, 'output_tokens') ? Json.num(u, 'output_tokens') : -1;
    out.push(StreamEvent.usage(input, output, Json.has(u, 'cache_read_input_tokens') ? cacheRead : -1));
  }

  private mapStop(): string {
    switch (this.stopReason) {
      case 'tool_use':
        return StopReason.TOOL_CALLS;
      case 'max_tokens':
        return StopReason.MAX_TOKENS;
      case 'refusal':
        return StopReason.REFUSAL;
      case 'end_turn':
      case 'stop_sequence':
        return this.sawToolUse ? StopReason.TOOL_CALLS : StopReason.END;
      default:
        return this.sawToolUse ? StopReason.TOOL_CALLS : StopReason.END;
    }
  }
}
