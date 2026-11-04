/** Keeps tool output within what is useful to send to a model. */
export class TextLimits {
  /** Keeps the head and tail of long text, noting how much was cut from the middle. */
  static middle(text: string, maxChars: number): string {
    if (text.length <= maxChars) {
      return text;
    }
    const head = Math.floor(maxChars * 0.6);
    const tail = maxChars - head;
    const cut = text.length - head - tail;
    return text.substring(0, head) + `\n\n[... ${cut} characters omitted ...]\n\n` + text.substring(text.length - tail);
  }

  static line(text: string, maxChars: number): string {
    return text.length <= maxChars ? text : text.substring(0, maxChars) + ' [line truncated]';
  }

  /** Removes ANSI escape sequences and carriage returns from terminal output. */
  static stripAnsi(text: string): string {
    return text
      .replace(new RegExp('\\x1b\\[[0-9;?]*[ -/]*[@-~]', 'g'), '')
      .replace(new RegExp('\\x1b\\][^\\x07]*\\x07', 'g'), '')
      .replace(new RegExp('\\r\\n', 'g'), '\n')
      .replace(new RegExp('\\r', 'g'), '');
  }

  static countLines(text: string): number {
    if (text.length === 0) {
      return 0;
    }
    let n = 1;
    for (let i = 0; i < text.length; i++) {
      if (text.charCodeAt(i) === 10) {
        n++;
      }
    }
    return text.endsWith('\n') ? n - 1 : n;
  }
}
