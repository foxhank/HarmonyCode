// HttpTransport for Node (tests only): streams the body through fetch.
import { CancelledError, CancelToken } from '../../entry/src/main/ets/core/llm/CancelToken';
import { HttpBodySink, HttpRequestSpec, HttpTransport } from '../../entry/src/main/ets/core/llm/HttpTransport';

export class NodeHttpTransport implements HttpTransport {
  async send(spec: HttpRequestSpec, sink: HttpBodySink, cancel: CancelToken): Promise<number> {
    const ctrl = new AbortController();
    const off = cancel.onCancel(() => ctrl.abort());
    const timer = setTimeout(() => ctrl.abort(), spec.timeoutMs);
    try {
      const res = await fetch(spec.url, { method: spec.method, headers: spec.headers, body: spec.method === 'GET' ? undefined : spec.body, signal: ctrl.signal });
      const reader = (res.body as ReadableStream<Uint8Array>).getReader();
      const dec = new TextDecoder('utf-8');
      for (;;) {
        const r = await reader.read();
        if (r.done) {
          break;
        }
        const t = dec.decode(r.value, { stream: true });
        if (t.length > 0) {
          sink.onText(t);
        }
      }
      const tail = dec.decode();
      if (tail.length > 0) {
        sink.onText(tail);
      }
      return res.status;
    } catch (e) {
      if (cancel.cancelled) {
        throw new CancelledError();
      }
      throw e;
    } finally {
      clearTimeout(timer);
      off();
    }
  }
}
