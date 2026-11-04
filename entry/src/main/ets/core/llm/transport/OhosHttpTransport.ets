import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { cancelledError, CancelToken } from '../CancelToken';
import { HttpBodySink, HttpMethod, HttpRequestSpec, HttpTransport } from '../HttpTransport';

/**
 * The request promise settles when the transfer completes, normally just after 'dataEnd'. If
 * 'dataEnd' is missing, finish once the body has been quiet this long.
 */
const END_GRACE_MS: number = 1000;

/** HttpTransport over the system network kit, streaming the body as it arrives. Follows redirects. */
export class OhosHttpTransport implements HttpTransport {
  send(spec: HttpRequestSpec, sink: HttpBodySink, cancel: CancelToken): Promise<number> {
    return new Promise<number>((resolve: (code: number) => void, reject: (e: Error) => void) => {
      const req = http.createHttp();
      const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      let settled = false;
      let ended = false;
      let status = -1;
      let lastDataAt = Date.now();
      let offCancel: () => void = () => {
      };

      const cleanup = (): void => {
        offCancel();
        try {
          req.off('dataReceive');
          req.off('dataEnd');
          req.destroy();
        } catch (e) {
          // already destroyed
        }
      };
      const finish = (): void => {
        if (settled || status < 0) {
          return;
        }
        settled = true;
        const tail = decoder.decodeToString(new Uint8Array(0), { stream: false });
        if (tail.length > 0) {
          sink.onText(tail);
        }
        cleanup();
        resolve(status);
      };
      const fail = (e: Error): void => {
        if (settled) {
          return;
        }
        settled = true;
        cleanup();
        reject(e);
      };

      offCancel = cancel.onCancel(() => fail(cancelledError()));
      req.on('dataReceive', (data: ArrayBuffer) => {
        if (settled) {
          return;
        }
        lastDataAt = Date.now();
        const text = decoder.decodeToString(new Uint8Array(data), { stream: true });
        if (text.length > 0) {
          sink.onText(text);
        }
      });
      req.on('dataEnd', () => {
        ended = true;
        finish();
      });
      req.requestInStream(spec.url, {
        method: spec.method === HttpMethod.GET ? http.RequestMethod.GET : http.RequestMethod.POST,
        header: spec.headers,
        extraData: spec.method === HttpMethod.GET || spec.body.length === 0 ? undefined : spec.body,
        readTimeout: spec.timeoutMs,
        connectTimeout: spec.connectTimeoutMs,
        usingCache: false
      }).then((code: number) => {
        status = code;
        if (ended) {
          finish();
          return;
        }
        const timer = setInterval(() => {
          if (settled) {
            clearInterval(timer);
          } else if (ended || Date.now() - lastDataAt >= END_GRACE_MS) {
            clearInterval(timer);
            finish();
          }
        }, END_GRACE_MS / 4);
      }).catch((err: BusinessError) => {
        fail(new Error(err.message !== undefined && err.message.length > 0 ? err.message : 'network error ' + err.code));
      });
    });
  }
}
