import { AppConfig } from '../common/AppConfig';
import { OutputSink, ShellBackend } from './ShellBackend';

/**
 * One terminal: keeps scrollback so the view can be rebuilt (rotation, layout change)
 * without losing output, and routes keystrokes to its backend.
 */
export class TerminalSession {
  private buffer: string = '';
  private sink: OutputSink | null = null;
  private backend: ShellBackend | null = null;
  private started: boolean = false;
  private cols: number = 80;
  private rows: number = 24;

  /** Sink the backend writes into. */
  readonly output: OutputSink = (data: string): void => {
    this.buffer += data;
    if (this.buffer.length > AppConfig.TERMINAL_SCROLLBACK_CHARS) {
      this.buffer = this.buffer.substring(this.buffer.length - AppConfig.TERMINAL_SCROLLBACK_CHARS);
    }
    if (this.sink !== null) {
      this.sink(data);
    }
  };

  setBackend(backend: ShellBackend): void {
    if (this.backend !== null) {
      this.backend.stop();
    }
    this.backend = backend;
    this.started = false;
  }

  label(): string {
    return this.backend !== null ? this.backend.label() : '';
  }

  /** Connects a view. Replays scrollback, then starts the backend on first attach. */
  attach(sink: OutputSink, cols: number, rows: number): void {
    this.sink = sink;
    this.cols = cols;
    this.rows = rows;
    if (this.buffer.length > 0) {
      sink(this.buffer);
    }
    if (!this.started && this.backend !== null) {
      this.started = true;
      this.backend.start(cols, rows);
    }
  }

  detach(): void {
    this.sink = null;
  }

  input(data: string): void {
    if (this.backend !== null) {
      this.backend.input(data);
    }
  }

  resize(cols: number, rows: number): void {
    if (cols === this.cols && rows === this.rows) {
      return;
    }
    this.cols = cols;
    this.rows = rows;
    if (this.backend !== null) {
      this.backend.resize(cols, rows);
    }
  }

  runLine(line: string): void {
    if (this.backend !== null) {
      this.backend.runLine(line);
    }
  }

  clearScrollback(): void {
    this.buffer = '';
  }

  dispose(): void {
    if (this.backend !== null) {
      this.backend.stop();
    }
    this.backend = null;
    this.sink = null;
  }
}
