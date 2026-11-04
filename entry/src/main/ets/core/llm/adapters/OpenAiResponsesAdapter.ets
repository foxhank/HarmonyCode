import { ApiAdapter, StreamDecoder } from '../ApiAdapter';
import { HttpRequestSpec } from '../HttpTransport';
import { Json, JsonObject } from '../Json';
import { ChatMessage, LlmRequest, MessagePart, PartKind, Role, StopReason, ToolSpec } from '../LlmTypes';
import { ApiFormat, endpointUrl, ModelInfo, ProviderConfig } from '../ProviderConfig';
import { StreamEvent } from '../StreamEvent';
import { AdapterSupport } from './AdapterSupport';

const PATH: string = '/responses';
const KEY_ITEM: string = 'o';
const ENCRYPTED_REASONING: string = 'reasoning.encrypted_content';

/**
 * OpenAI Responses API (`POST /responses`). Runs stateless (`store: false`): the whole
 * conversation is sent each turn, with reasoning carried as encrypted items.
 */
export class OpenAiResponsesAdapter implements ApiAdapter {
  readonly format: string = ApiFormat.OPENAI_RESPONSES;

  buildRequest(provider: ProviderConfig, model: ModelInfo, request: LlmRequest): HttpRequestSpec {
    const body: JsonObject = {
      'model': model.id,
      'input': OpenAiResponsesAdapter.input(request.messages),
      'stream': true,
      'store': false
    };
    if (request.system.length > 0) {
      body['instructions'] = request.system;
    }
    if (request.tools.length > 0) {
      body['tools'] = request.tools.map((t: ToolSpec): Object => OpenAiResponsesAdapter.tool(t));
      body['parallel_tool_calls'] = true;
    }
    const maxTokens = request.maxOutputTokens > 0 ? request.maxOutputTokens : model.maxOutputTokens;
    if (maxTokens > 0) {
      body['max_output_tokens'] = maxTokens;
    }
    if (!Number.isNaN(request.temperature)) {
      body['temperature'] = request.temperature;
    }
    if (model.reasoning) {
      body['include'] = [ENCRYPTED_REASONING];
      const reasoning: JsonObject = { 'summary': 'auto' };
      body['reasoning'] = reasoning;
    }
    const auth: Record<string, string> = {};
    if (provider.apiKey.length > 0) {
      auth['Authorization'] = 'Bearer ' + provider.apiKey;
    }
    return AdapterSupport.spec(provider, endpointUrl(provider.baseUrl, PATH), auth, body);
  }

  newDecoder(): StreamDecoder {
    return new ResponsesDecoder();
  }

  errorMessage(status: number, body: string): string {
    return AdapterSupport.errorMessage(status, body);
  }

  private static tool(t: ToolSpec): JsonObject {
    const o: JsonObject = {
      'type': 'function', 'name': t.name, 'description': t.description, 'parameters': t.parameters, 'strict': false
    };
    return o;
  }

  /** Flattens messages into Responses input items, keeping the original order of parts. */
  private static input(messages: ChatMessage[]): Object[] {
    const out: Object[] = [];
    for (const m of messages) {
      const assistant = m.role === Role.ASSISTANT;
      let text = '';
      const flushText = (): void => {
        if (text.length === 0) {
          return;
        }
        out.push(OpenAiResponsesAdapter.messageItem(assistant, text));
        text = '';
      };
      for (const p of m.parts) {
        if (p.kind === PartKind.TEXT) {
          text += (text.length > 0 && !assistant ? '\n\n' : '') + p.text;
          continue;
        }
        flushText();
        const item = OpenAiResponsesAdapter.partItem(p);
        if (item !== null) {
          out.push(item);
        }
      }
      flushText();
    }
    return out;
  }

  private static messageItem(assistant: boolean, text: string): JsonObject {
    const content: JsonObject = { 'type': assistant ? 'output_text' : 'input_text', 'text': text };
    const o: JsonObject = { 'role': assistant ? 'assistant' : 'user', 'content': [content] };
    return o;
  }

  private static partItem(p: MessagePart): JsonObject | null {
    if (p.kind === PartKind.TOOL_CALL) {
      const o: JsonObject = {
        'type': 'function_call', 'call_id': p.callId, 'name': p.toolName,
        'arguments': AdapterSupport.argumentsOrEmpty(p.argumentsJson)
      };
      return o;
    }
    if (p.kind === PartKind.TOOL_RESULT) {
      const o: JsonObject = { 'type': 'function_call_output', 'call_id': p.callId, 'output': p.text };
      return o;
    }
    if (p.kind === PartKind.REASONING && p.signature.length > 0) {
      const summary: Object[] = [];
      if (p.text.length > 0) {
        const s: JsonObject = { 'type': 'summary_text', 'text': p.text };
        summary.push(s);
      }
      const o: JsonObject = { 'type': 'reasoning', 'summary': summary, 'encrypted_content': p.signature };
      if (p.callId.length > 0) {
        o['id'] = p.callId;
      }
      return o;
    }
    return null;
  }
}

class ResponsesDecoder implements StreamDecoder {
  private status: string = '';
  private incompleteReason: string = '';
  private sawToolCalls: boolean = false;
  /** Item id -> output index, for events that only name the item. */
  private itemKeys: Map<string, string> = new Map();

  onSse(event: string, data: string): StreamEvent[] {
    const o = Json.parseObject(data);
    if (o === null) {
      return [];
    }
    const type = Json.str(o, 'type', event);
    const out: StreamEvent[] = [];
    switch (type) {
      case 'response.output_item.added':
        this.itemStart(this.keyOf(o), Json.obj(o, 'item'), out);
        break;
      case 'response.output_item.done':
        this.itemDone(this.keyOf(o), Json.obj(o, 'item'), out);
        break;
      case 'response.output_text.delta':
      case 'response.refusal.delta':
        out.push(StreamEvent.text(this.keyOf(o), Json.str(o, 'delta')));
        break;
      case 'response.reasoning_summary_text.delta':
      case 'response.reasoning_text.delta':
        out.push(StreamEvent.reasoning(this.keyOf(o), Json.str(o, 'delta')));
        break;
      case 'response.reasoning_summary_part.added':
        // Separate summary paragraphs.
        if (Json.num(o, 'summary_index') > 0) {
          out.push(StreamEvent.reasoning(this.keyOf(o), '\n\n'));
        }
        break;
      case 'response.function_call_arguments.delta':
        out.push(StreamEvent.toolDelta(this.keyOf(o), Json.str(o, 'delta')));
        break;
      case 'response.function_call_arguments.done':
        out.push(StreamEvent.toolArguments(this.keyOf(o), Json.str(o, 'arguments')));
        break;
      case 'response.completed':
      case 'response.incomplete':
      case 'response.failed':
        this.final(Json.obj(o, 'response'), out);
        break;
      case 'error':
        out.push(StreamEvent.error(Json.str(o, 'message', Json.str(Json.obj(o, 'error'), 'message', data))));
        break;
      default:
        break;
    }
    return out;
  }

  onBody(body: JsonObject): StreamEvent[] {
    const out: StreamEvent[] = [];
    const items = Json.objects(body, 'output');
    for (let i = 0; i < items.length; i++) {
      const key = KEY_ITEM + i;
      this.itemStart(key, items[i], out);
      this.itemDone(key, items[i], out);
      if (Json.str(items[i], 'type') === 'message') {
        for (const c of Json.objects(items[i], 'content')) {
          const t = Json.str(c, 'text', Json.str(c, 'refusal'));
          if (t.length > 0) {
            out.push(StreamEvent.text(key, t));
          }
        }
      }
    }
    this.final(body, out);
    return out;
  }

  finish(): StreamEvent[] {
    let reason = this.sawToolCalls ? StopReason.TOOL_CALLS : StopReason.END;
    if (this.status === 'incomplete' && this.incompleteReason === 'max_output_tokens') {
      reason = StopReason.MAX_TOKENS;
    } else if (this.status === 'incomplete' && this.incompleteReason === 'content_filter') {
      reason = StopReason.REFUSAL;
    }
    return [StreamEvent.stop(reason)];
  }

  private keyOf(o: JsonObject): string {
    if (Json.has(o, 'output_index')) {
      return KEY_ITEM + Json.num(o, 'output_index');
    }
    return this.itemKeys.get(Json.str(o, 'item_id')) ?? KEY_ITEM + Json.str(o, 'item_id');
  }

  private itemStart(key: string, item: JsonObject | null, out: StreamEvent[]): void {
    const id = Json.str(item, 'id');
    if (id.length > 0) {
      this.itemKeys.set(id, key);
    }
    if (Json.str(item, 'type') === 'function_call') {
      this.sawToolCalls = true;
      out.push(StreamEvent.toolStart(key, Json.str(item, 'call_id', id), Json.str(item, 'name')));
    }
  }

  private itemDone(key: string, item: JsonObject | null, out: StreamEvent[]): void {
    const type = Json.str(item, 'type');
    if (type === 'function_call') {
      out.push(StreamEvent.toolArguments(key, Json.str(item, 'arguments')));
    } else if (type === 'reasoning') {
      const enc = Json.str(item, 'encrypted_content');
      // Summary text streams as deltas; only fill it from the item when nothing streamed.
      let summary = '';
      for (const s of Json.objects(item, 'summary')) {
        summary += (summary.length > 0 ? '\n\n' : '') + Json.str(s, 'text');
      }
      out.push(StreamEvent.reasoningMeta(key, enc, Json.str(item, 'id'), summary));
    }
  }

  private final(resp: JsonObject | null, out: StreamEvent[]): void {
    if (resp === null) {
      return;
    }
    this.status = Json.str(resp, 'status');
    this.incompleteReason = Json.str(Json.obj(resp, 'incomplete_details'), 'reason');
    const err = Json.obj(resp, 'error');
    if (err !== null) {
      out.push(StreamEvent.error(Json.str(err, 'code', 'error') + ': ' + Json.str(err, 'message')));
    }
    const u = Json.obj(resp, 'usage');
    if (u !== null) {
      out.push(StreamEvent.usage(Json.num(u, 'input_tokens'), Json.num(u, 'output_tokens'),
        Json.num(Json.obj(u, 'input_tokens_details'), 'cached_tokens')));
    }
  }
}
