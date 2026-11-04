import { CancelToken } from './CancelToken';

export class HttpMethod {
  static readonly GET: string = 'GET';
  static readonly POST: string = 'POST';
}

/** An HTTP request. `body` is sent for POST ('' = none). */
export interface HttpRequestSpec {
  method: string;
  url: string;
  headers: Record<string, string>;
  body: string;
  timeoutMs: number;
  connectTimeoutMs: number;
}

/** Receives the response body as decoded UTF-8 text, chunk by chunk, as it arrives. */
export interface HttpBodySink {
  onText(chunk: string): void;
}

/**
 * Minimal streaming HTTP client the model layer and the web tools depend on. The app implements
 * it with the system network kit; tests implement it with Node's fetch. Rejects on network
 * failure and with CancelledError when cancelled; resolves with the HTTP status once the body
 * has ended.
 */
export interface HttpTransport {
  send(spec: HttpRequestSpec, sink: HttpBodySink, cancel: CancelToken): Promise<number>;
}
