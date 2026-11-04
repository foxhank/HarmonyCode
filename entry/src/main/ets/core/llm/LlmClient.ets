import { AdapterRegistry } from './AdapterRegistry';
import { ApiAdapter } from './ApiAdapter';
import { CancelToken } from './CancelToken';
import { HttpBodySink, HttpTransport } from './HttpTransport';
import { Json } from './Json';
import { LlmError } from './LlmError';
import { LlmDefaults, LlmRequest, LlmResult, LlmStreamListener } from './LlmTypes';
import { ModelInfo, ProviderConfig } from './ProviderConfig';
import { ResponseAssembler, StreamError } from './ResponseAssembler';
import { SseParser } from './SseParser';

/** Body text kept for error messages and for servers that answer without streaming. */
const MAX_RAW_BODY: number = 1024 * 1024;

/** Collects one HTTP response: feeds SSE events to the decoder and keeps the raw text. */
class ResponseSink implements HttpBodySink {
  raw: string = '';
  sawEvents: boolean = false;
  private parser: SseParser;

  constructor(onEvent: (event: string, data: string) => void) {
    this.parser = new SseParser((event: string, data: string) => {
      this.sawEvents = true;
      onEvent(event, data);
    });
  }

  onText(chunk: string): void {
    if (this.raw.length < MAX_RAW_BODY) {
      this.raw += chunk;
    }
    this.parser.feed(chunk);
  }

  end(): void {
    this.parser.end();
  }
}

/**
 * The single entry point for calling any model. Picks the adapter for the provider's format,
 * streams the answer, retries transient failures, and returns a provider-neutral result.
 */
export class LlmClient {
  private transport: HttpTransport;
  private registry: AdapterRegistry;

  constructor(transport: HttpTransport, registry: AdapterRegistry = AdapterRegistry.standard()) {
    this.transport = transport;
    this.registry = registry;
  }

  async complete(provider: ProviderConfig, model: ModelInfo, request: LlmRequest,
    listener: LlmStreamListener | null, cancel: CancelToken): Promise<LlmResult> {
    const adapter = this.registry.get(provider.format);
    if (adapter === undefined) {
      throw new LlmError('Unsupported API format: ' + provider.format, 0, false);
    }
    let attempt = 0;
    while (true) {
      cancel.throwIfCancelled();
      const assembler = new ResponseAssembler(listener);
      try {
        return await this.once(adapter, provider, model, request, assembler, cancel);
      } catch (e) {
        if (CancelToken.isCancellation(e as Error) || cancel.cancelled) {
          throw e as Error;
        }
        const err = LlmClient.normalize(e as Error);
        attempt++;
        // Never retry after output reached the listener: the UI would show it twice.
        if (!err.retryable || assembler.hasOutput || attempt > LlmDefaults.MAX_RETRIES) {
          throw err;
        }
        const delay = Math.min(LlmDefaults.RETRY_MAX_DELAY_MS,
          LlmDefaults.RETRY_BASE_DELAY_MS * Math.pow(2, attempt - 1));
        await cancel.sleep(delay + Math.floor(Math.random() * LlmDefaults.RETRY_BASE_DELAY_MS));
      }
    }
  }

  private async once(adapter: ApiAdapter, provider: ProviderConfig, model: ModelInfo, request: LlmRequest,
    assembler: ResponseAssembler, cancel: CancelToken): Promise<LlmResult> {
    const decoder = adapter.newDecoder();
    const spec = adapter.buildRequest(provider, model, request);
    let streamError: Error | null = null;
    const sink = new ResponseSink((event: string, data: string) => {
      if (streamError !== null) {
        return;
      }
      try {
        assembler.accept(decoder.onSse(event, data));
      } catch (e) {
        streamError = e as Error;
      }
    });
    const status = await this.transport.send(spec, sink, cancel);
    sink.end();
    if (status < 200 || status >= 300) {
      throw new LlmError(adapter.errorMessage(status, sink.raw), status, LlmError.isRetryableStatus(status));
    }
    if (streamError !== null) {
      throw new LlmError((streamError as Error).message, 0, false);
    }
    if (!sink.sawEvents) {
      // The server ignored `stream: true` and sent one JSON document.
      const body = Json.parseObject(sink.raw);
      if (body === null) {
        throw new LlmError('Unexpected response: ' + sink.raw.substring(0, 300), status, false);
      }
      assembler.accept(decoder.onBody(body));
    }
    assembler.accept(decoder.finish());
    return assembler.result();
  }

  private static normalize(e: Error): LlmError {
    if (e instanceof LlmError) {
      return e;
    }
    if (e instanceof StreamError) {
      return new LlmError(e.message, 0, false);
    }
    // Transport failures (DNS, reset, timeout) are transient.
    return new LlmError(e.message, 0, true);
  }
}
