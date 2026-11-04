/** Called for each complete server-sent event. `event` is '' when the stream gave no name. */
export type SseHandler = (event: string, data: string) => void;

/**
 * Incremental parser for text/event-stream bodies (WHATWG rules): handles chunks split anywhere,
 * CRLF / LF / CR line endings, multi-line data fields and comment lines.
 */
export class SseParser {
  private handler: SseHandler;
  private pending: string = '';
  private eventName: string = '';
  private dataLines: string[] = [];
  private sawCr: boolean = false;

  constructor(handler: SseHandler) {
    this.handler = handler;
  }

  feed(chunk: string): void {
    let text = chunk;
    // A CR at the end of the previous chunk may be the first half of CRLF.
    if (this.sawCr && text.startsWith('\n')) {
      text = text.substring(1);
    }
    this.sawCr = text.endsWith('\r');
    let buf = this.pending + text;
    let start = 0;
    for (let i = 0; i < buf.length; i++) {
      const c = buf.charAt(i);
      if (c !== '\n' && c !== '\r') {
        continue;
      }
      this.line(buf.substring(start, i));
      if (c === '\r' && i + 1 < buf.length && buf.charAt(i + 1) === '\n') {
        i++;
      }
      start = i + 1;
    }
    buf = buf.substring(start);
    this.pending = buf;
  }

  /** Flushes a last event that wasn't followed by a blank line. */
  end(): void {
    if (this.pending.length > 0) {
      this.line(this.pending);
      this.pending = '';
    }
    this.dispatch();
  }

  private line(line: string): void {
    if (line.length === 0) {
      this.dispatch();
      return;
    }
    if (line.startsWith(':')) {
      return;
    }
    const colon = line.indexOf(':');
    const field = colon < 0 ? line : line.substring(0, colon);
    let value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }
    if (field === 'event') {
      this.eventName = value;
    } else if (field === 'data') {
      this.dataLines.push(value);
    }
  }

  private dispatch(): void {
    if (this.dataLines.length > 0) {
      const data = this.dataLines.join('\n');
      const name = this.eventName;
      this.dataLines = [];
      this.eventName = '';
      this.handler(name, data);
      return;
    }
    this.eventName = '';
  }
}
