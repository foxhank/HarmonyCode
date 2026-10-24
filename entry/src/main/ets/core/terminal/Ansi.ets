/** ANSI escape helpers for terminal output. */
export class Ansi {
  static readonly ESC: string = '\x1b';
  static readonly CSI: string = '\x1b[';
  static readonly RESET: string = '\x1b[0m';
  static readonly CRLF: string = '\r\n';
  static readonly CLEAR_LINE_RIGHT: string = '\x1b[K';
  static readonly CLEAR_SCREEN: string = '\x1b[2J\x1b[3J\x1b[H';

  static bold(s: string): string {
    return '\x1b[1m' + s + Ansi.RESET;
  }

  static dim(s: string): string {
    return '\x1b[2m' + s + Ansi.RESET;
  }

  static red(s: string): string {
    return '\x1b[31m' + s + Ansi.RESET;
  }

  static green(s: string): string {
    return '\x1b[32m' + s + Ansi.RESET;
  }

  static yellow(s: string): string {
    return '\x1b[33m' + s + Ansi.RESET;
  }

  static blue(s: string): string {
    return '\x1b[34m' + s + Ansi.RESET;
  }

  static cyan(s: string): string {
    return '\x1b[36m' + s + Ansi.RESET;
  }

  static boldGreen(s: string): string {
    return '\x1b[1;32m' + s + Ansi.RESET;
  }

  static boldBlue(s: string): string {
    return '\x1b[1;34m' + s + Ansi.RESET;
  }

  static cursorLeft(n: number): string {
    return n > 0 ? Ansi.CSI + n + 'D' : '';
  }

  /** Visible length (escape sequences removed). */
  static visibleLength(s: string): number {
    return s.replace(new RegExp('\\x1b\\[[0-9;]*[A-Za-z]', 'g'), '').length;
  }

  /** Normalizes line endings to CRLF for terminal output. */
  static crlf(s: string): string {
    return s.replace(new RegExp('\\r?\\n', 'g'), Ansi.CRLF);
  }
}
