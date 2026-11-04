import { HttpMethod, HttpRequestSpec } from '../HttpTransport';
import { Json, JsonObject } from '../Json';
import { LlmDefaults } from '../LlmTypes';
import { ProviderConfig } from '../ProviderConfig';

const MAX_ERROR_CHARS: number = 600;

/** Pieces shared by the adapters. */
export class AdapterSupport {
  /** JSON POST with the provider's extra headers on top of `auth`. */
  static spec(provider: ProviderConfig, url: string, auth: Record<string, string>, body: JsonObject): HttpRequestSpec {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream'
    };
    for (const k of Object.keys(auth)) {
      headers[k] = auth[k];
    }
    for (const k of Object.keys(provider.headers)) {
      headers[k] = provider.headers[k];
    }
    return {
      method: HttpMethod.POST,
      url: url,
      headers: headers,
      body: JSON.stringify(body),
      timeoutMs: LlmDefaults.REQUEST_TIMEOUT_MS,
      connectTimeoutMs: LlmDefaults.CONNECT_TIMEOUT_MS
    };
  }

  /** `{"error":{"message":...}}`, `{"error":"..."}`, `{"message":...}` or the raw text. */
  static errorMessage(status: number, body: string): string {
    const o = Json.parseObject(body);
    let msg = '';
    if (o !== null) {
      const err = Json.obj(o, 'error');
      if (err !== null) {
        msg = Json.str(err, 'message');
        const type = Json.str(err, 'type');
        if (msg.length > 0 && type.length > 0) {
          msg = type + ': ' + msg;
        }
      } else {
        msg = Json.str(o, 'error', Json.str(o, 'message', Json.str(o, 'detail')));
      }
    }
    if (msg.length === 0) {
      msg = body.trim();
    }
    if (msg.length > MAX_ERROR_CHARS) {
      msg = msg.substring(0, MAX_ERROR_CHARS) + '…';
    }
    return 'HTTP ' + status + (msg.length > 0 ? ' — ' + msg : '');
  }

  /** Tool arguments must be a JSON object; models occasionally send '' for "no arguments". */
  static argumentsOrEmpty(json: string): string {
    return json.trim().length === 0 ? '{}' : json;
  }

  /** Parses tool arguments for formats that need an object (Anthropic); invalid JSON becomes {}. */
  static argumentsObject(json: string): JsonObject {
    const o = Json.parseObject(json);
    if (o !== null) {
      return o;
    }
    const empty: JsonObject = {};
    return empty;
  }
}
