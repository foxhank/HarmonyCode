import { HttpRequestSpec } from './HttpTransport';
import { JsonObject } from './Json';
import { LlmRequest } from './LlmTypes';
import { ModelInfo, ProviderConfig } from './ProviderConfig';
import { StreamEvent } from './StreamEvent';

/** Turns one provider's stream (or non-streamed body) into normalized events. One per call. */
export interface StreamDecoder {
  /** One server-sent event. */
  onSse(event: string, data: string): StreamEvent[];
  /** A complete JSON response, for servers that ignore `stream: true`. */
  onBody(body: JsonObject): StreamEvent[];
  /** End of stream: emits anything still buffered (e.g. the stop reason). */
  finish(): StreamEvent[];
}

/**
 * Knows one wire format: how to encode a request and decode its stream. Adapters are
 * stateless; everything about a single call lives in its StreamDecoder.
 */
export interface ApiAdapter {
  readonly format: string;
  buildRequest(provider: ProviderConfig, model: ModelInfo, request: LlmRequest): HttpRequestSpec;
  newDecoder(): StreamDecoder;
  /** Human-readable message from an error response body. */
  errorMessage(status: number, body: string): string;
}
