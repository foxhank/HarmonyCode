import { AppConfig } from '../../common/AppConfig';
import { Ansi } from '../Ansi';
import { OutputSink } from '../ShellBackend';

/** Result of tab completion: text to insert, or candidates to list. */
export interface Completion {
  insert: string;
  candidates: string[];
}

export type LineHandler = (line: string) => void;
export type Completer = (lineBeforeCursor: string) => Completion;

// Control characters.
const CR: string = '\r';
const LF: string = '\n';
const DEL: string = '\x7f';
const BS: string = '\b';
const TAB: string = '\t';
const CTRL_A: string = '\x01';
const CTRL_C: string = '\x03';
const CTRL_D: string = '\x04';
const CTRL_E: string = '\x05';
const CTRL_K: string = '\x0b';
const CTRL_L: string = '\x0c';
const CTRL_U: string = '\x15';
const CTRL_W: string = '\x17';
const MAX_ESCAPE_LEN: number = 8;

/** Readline-style editing: cursor movement, history, completion. */
export class LineEditor {
  private out: OutputSink;
  private onLine: LineHandler;
  private completer: Completer;
  private line: string = '';
  private cursor: number = 0;
  private prompt: string = '';
  private history: string[] = [];
  private historyIndex: number = -1;
  private draft: string = '';
  private escape: string = '';
  private active: boolean = false;

  constructor(out: OutputSink, onLine: LineHandler, completer: Completer) {
    this.out = out;
    this.onLine = onLine;
    this.completer = completer;
  }

  /** Shows the prompt and starts accepting input. */
  showPrompt(prompt: string): void {
    this.prompt = prompt;
    this.line = '';
    this.cursor = 0;
    this.historyIndex = -1;
    this.active = true;
    this.out(prompt);
  }

  /** While a command runs, input is ignored (except Ctrl+C, reported via onInterrupt). */
  isActive(): boolean {
    return this.active;
  }

  historyList(): string[] {
    return this.history.slice();
  }

  feed(data: string, onInterrupt: () => void): void {
    for (let i = 0; i < data.length; i++) {
      const ch = data.charAt(i);
      if (this.escape.length > 0) {
        this.escape += ch;
        if (this.handleEscape()) {
          this.escape = '';
        } else if (this.escape.length > MAX_ESCAPE_LEN) {
          this.escape = '';
        }
        continue;
      }
      if (ch === Ansi.ESC) {
        this.escape = ch;
        continue;
      }
      if (ch === CTRL_C) {
        if (this.active) {
          this.out('^C' + Ansi.CRLF);
          this.active = false;
          this.showPrompt(this.prompt);
        } else {
          onInterrupt();
        }
        continue;
      }
      if (!this.active) {
        continue;
      }
      this.handleChar(ch, data.charAt(i + 1));
      if (ch === CR && data.charAt(i + 1) === LF) {
        i++;
      }
    }
  }

  private handleChar(ch: string, next: string): void {
    switch (ch) {
      case CR:
      case LF:
        this.submit();
        break;
      case DEL:
      case BS:
        if (this.cursor > 0) {
          this.line = this.line.substring(0, this.cursor - 1) + this.line.substring(this.cursor);
          this.cursor--;
          this.redraw();
        }
        break;
      case TAB:
        this.complete();
        break;
      case CTRL_A:
        this.cursor = 0;
        this.redraw();
        break;
      case CTRL_E:
        this.cursor = this.line.length;
        this.redraw();
        break;
      case CTRL_K:
        this.line = this.line.substring(0, this.cursor);
        this.redraw();
        break;
      case CTRL_U:
        this.line = this.line.substring(this.cursor);
        this.cursor = 0;
        this.redraw();
        break;
      case CTRL_W:
        this.deleteWordBack();
        break;
      case CTRL_L:
        this.out(Ansi.CLEAR_SCREEN);
        this.redraw();
        break;
      case CTRL_D:
        break;
      default:
        if (ch >= ' ') {
          this.insert(ch);
        }
    }
  }

  /** Returns true when the escape sequence is complete (handled or ignored). */
  private handleEscape(): boolean {
    const seq = this.escape;
    if (seq.length < 3) {
      return false;
    }
    const last = seq.charAt(seq.length - 1);
    const isFinal = (last >= 'A' && last <= 'Z') || (last >= 'a' && last <= 'z') || last === '~';
    if (!isFinal) {
      return false;
    }
    const body = seq.substring(2);
    if (body === 'A') {
      this.historyMove(1);
    } else if (body === 'B') {
      this.historyMove(-1);
    } else if (body === 'C' && this.cursor < this.line.length) {
      this.cursor++;
      this.redraw();
    } else if (body === 'D' && this.cursor > 0) {
      this.cursor--;
      this.redraw();
    } else if (body === 'H' || body === '1~') {
      this.cursor = 0;
      this.redraw();
    } else if (body === 'F' || body === '4~') {
      this.cursor = this.line.length;
      this.redraw();
    } else if (body === '3~' && this.cursor < this.line.length) {
      this.line = this.line.substring(0, this.cursor) + this.line.substring(this.cursor + 1);
      this.redraw();
    }
    return true;
  }

  private insert(text: string): void {
    this.line = this.line.substring(0, this.cursor) + text + this.line.substring(this.cursor);
    this.cursor += text.length;
    if (this.cursor === this.line.length) {
      this.out(text); // fast path: typing at the end
    } else {
      this.redraw();
    }
  }

  private deleteWordBack(): void {
    let i = this.cursor;
    while (i > 0 && this.line.charAt(i - 1) === ' ') {
      i--;
    }
    while (i > 0 && this.line.charAt(i - 1) !== ' ') {
      i--;
    }
    this.line = this.line.substring(0, i) + this.line.substring(this.cursor);
    this.cursor = i;
    this.redraw();
  }

  private submit(): void {
    const line = this.line;
    this.out(Ansi.CRLF);
    this.active = false;
    if (line.trim().length > 0 && this.history[this.history.length - 1] !== line) {
      this.history.push(line);
      if (this.history.length > AppConfig.TERMINAL_HISTORY_SIZE) {
        this.history.shift();
      }
    }
    this.onLine(line);
  }

  private historyMove(delta: number): void {
    if (this.history.length === 0) {
      return;
    }
    if (this.historyIndex === -1) {
      this.draft = this.line;
    }
    const next = this.historyIndex + delta;
    if (next < -1 || next >= this.history.length) {
      return;
    }
    this.historyIndex = next;
    this.line = next === -1 ? this.draft : this.history[this.history.length - 1 - next];
    this.cursor = this.line.length;
    this.redraw();
  }

  private complete(): void {
    const result = this.completer(this.line.substring(0, this.cursor));
    if (result.insert.length > 0) {
      this.insert(result.insert);
    } else if (result.candidates.length > 1) {
      this.out(Ansi.CRLF + result.candidates.join('  ') + Ansi.CRLF);
      this.out(this.prompt + this.line + Ansi.cursorLeft(this.line.length - this.cursor));
    }
  }

  private redraw(): void {
    this.out('\r' + this.prompt + this.line + Ansi.CLEAR_LINE_RIGHT + Ansi.cursorLeft(this.line.length - this.cursor));
  }
}
