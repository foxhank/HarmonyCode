import { ApiAdapter, StreamDecoder } from '../ApiAdapter';
import { HttpRequestSpec } from '../HttpTransport';
import { Json, JsonObject } from '../Json';
import { ChatMessage, LlmRequest, PartKind, Role, StopReason, ToolSpec } from '../LlmTypes';
import { ApiFormat, endpointUrl, ModelInfo, ProviderConfig } from '../ProviderConfig';
import { StreamEvent } from '../StreamEvent';
import { AdapterSupport } from './AdapterSupport';

const PATH: string = '/chat/completions';
const DONE: string = '[DONE]';
const KEY_TEXT: string = 'text';
const KEY_REASONING: string = 'reasoning';
const KEY_TOOL: string = 'tool:';

/**
 * OpenAI Chat Completions (`POST /chat/completions`), also spoken by DeepSeek, Qwen, Kimi, GLM,
 * OpenRouter, Ollama and most other "OpenAI-compatible" servers.
 */
export class OpenAiChatAdapter implements ApiAdapter {
  readonly format: string = ApiFormat.OPENAI_CHAT;

  buildRequest(provider: ProviderConfig, model: ModelInfo, request: LlmRequest): HttpRequestSpec {
    const body: JsonObject = {
      'model': model.id,
      'messages': OpenAiChatAdapter.messages(request),
      'stream': true,
      'stream_options': OpenAiChatAdapter.streamOptions()
    };
    if (request.tools.length > 0) {
      body['tools'] = request.tools.map((t: ToolSpec): Object => OpenAiChatAdapter.tool(t));
    }
    const maxTokens = request.maxOutputTokens > 0 ? request.maxOutputTokens : model.maxOutputTokens;
    if (maxTokens > 0) {
      body['max_tokens'] = maxTokens;
    }
    if (!Number.isNaN(request.temperature)) {
      body['temperature'] = request.temperature;
    }
    const auth: Record<string, string> = {};
    if (provider.apiKey.length > 0) {
      auth['Authorization'] = 'Bearer ' + provider.apiKey;
    }
    return AdapterSupport.spec(provider, endpointUrl(provider.baseUrl, PATH), auth, body);
  }

  newDecoder(): StreamDecoder {
    return new ChatDecoder();
  }

  errorMessage(status: number, body: string): string {
    return AdapterSupport.errorMessage(status, body);
  }

  private static streamOptions(): JsonObject {
    const o: JsonObject = { 'include_usage': true };
    return o;
  }

  private static tool(t: ToolSpec): JsonObject {
    const fn: JsonObject = { 'name': t.name, 'description': t.description, 'parameters': t.parameters };
    const o: JsonObject = { 'type': 'function', 'function': fn };
    return o;
  }

  /** System prompt first; tool results become `tool` messages; reasoning is echoed when present. */
  private static messages(request: LlmRequest): Object[] {
    const out: Object[] = [];
    if (request.system.length > 0) {
      const sys: JsonObject = { 'role': 'system', 'content': request.system };
      out.push(sys);
    }
    for (const m of request.messages) {
      if (m.role === Role.ASSISTANT) {
        out.push(OpenAiChatAdapter.assistant(m));
        continue;
      }
      let text = '';
      for (const p of m.parts) {
        if (p.kind === PartKind.TOOL_RESULT) {
          const tm: JsonObject = { 'role': 'tool', 'tool_call_id': p.callId, 'content': p.text };
          out.push(tm);
        } else if (p.kind === PartKind.TEXT) {
          text += (text.length > 0 ? '\n\n' : '') + p.text;
        }
      }
      if (text.length > 0) {
        const um: JsonObject = { 'role': 'user', 'content': text };
        out.push(um);
      }
    }
    return out;
  }

  private static assistant(m: ChatMessage): JsonObject {
    let text = '';
    let reasoning = '';
    const calls: Object[] = [];
    for (const p of m.parts) {
      if (p.kind === PartKind.TEXT) {
        text += p.text;
      } else if (p.kind === PartKind.REASONING) {
        reasoning += p.text;
      } else if (p.kind === PartKind.TOOL_CALL) {
        const fn: JsonObject = { 'name': p.toolName, 'arguments': AdapterSupport.argumentsOrEmpty(p.argumentsJson) };
        const call: JsonObject = { 'id': p.callId, 'type': 'function', 'function': fn };
        calls.push(call);
      }
    }
    const msg: JsonObject = { 'role': 'assistant', 'content': text };
    if (calls.length > 0) {
      msg['tool_calls'] = calls;
    }
    // DeepSeek and other reasoning servers require their reasoning back during a tool-use turn.
    if (reasoning.length > 0) {
      msg['reasoning_content'] = reasoning;
    }
    return msg;
  }
}

class ChatDecoder implements StreamDecoder {
  private finishReason: string = '';
  private sawToolCalls: boolean = false;

  onSse(event: string, data: string): StreamEvent[] {
    if (data.trim() === DONE) {
      return [];
    }
    const o = Json.parseObject(data);
    if (o === null) {
      return [];
    }
    return this.chunk(o, false);
  }

  onBody(body: JsonObject): StreamEvent[] {
    return this.chunk(body, true);
  }

  finish(): StreamEvent[] {
    return [StreamEvent.stop(this.stopReason())];
  }

  private chunk(o: JsonObject, whole: boolean): StreamEvent[] {
    const out: StreamEvent[] = [];
    const err = Json.obj(o, 'error');
    if (err !== null) {
      out.push(StreamEvent.error(Json.str(err, 'message', JSON.stringify(err))));
      return out;
    }
    for (const choice of Json.objects(o, 'choices')) {
      // Streamed chunks carry `delta`; a complete body carries `message`.
      const delta = Json.obj(choice, whole ? 'message' : 'delta');
      if (delta !== null) {
        this.delta(delta, out);
      }
      const fr = Json.str(choice, 'finish_reason');
      if (fr.length > 0) {
        this.finishReason = fr;
      }
    }
    const usage = Json.obj(o, 'usage');
    if (usage !== null) {
      const details = Json.obj(usage, 'prompt_tokens_details');
      const cached = details !== null ? Json.num(details, 'cached_tokens') : Json.num(usage, 'prompt_cache_hit_tokens');
      out.push(StreamEvent.usage(Json.num(usage, 'prompt_tokens'), Json.num(usage, 'completion_tokens'), cached));
    }
    return out;
  }

  private delta(d: JsonObject, out: StreamEvent[]): void {
    const reasoning = Json.str(d, 'reasoning_content', Json.str(d, 'reasoning'));
    if (reasoning.length > 0) {
      out.push(StreamEvent.reasoning(KEY_REASONING, reasoning));
    }
    const content = Json.str(d, 'content');
    if (content.length > 0) {
      out.push(StreamEvent.text(KEY_TEXT, content));
    }
    const calls = Json.objects(d, 'tool_calls');
    for (let i = 0; i < calls.length; i++) {
      const c = calls[i];
      this.sawToolCalls = true;
      const key = KEY_TOOL + Json.num(c, 'index', i);
      const fn = Json.obj(c, 'function');
      const id = Json.str(c, 'id');
      const name = Json.str(fn, 'name');
      if (id.length > 0 || name.length > 0) {
        out.push(StreamEvent.toolStart(key, id, name));
      }
      const args = Json.str(fn, 'arguments');
      if (args.length > 0) {
        out.push(StreamEvent.toolDelta(key, args));
      }
    }
  }

  private stopReason(): string {
    switch (this.finishReason) {
      case 'tool_calls':
      case 'function_call':
        return StopReason.TOOL_CALLS;
      case 'length':
        return StopReason.MAX_TOKENS;
      case 'content_filter':
        return StopReason.REFUSAL;
      case 'stop':
        // Some servers report "stop" even when they returned tool calls.
        return this.sawToolCalls ? StopReason.TOOL_CALLS : StopReason.END;
      default:
        return this.sawToolCalls ? StopReason.TOOL_CALLS : StopReason.END;
    }
  }
}
