/** One command of a command list and how it is joined to the previous one. */
export interface CommandStep {
  /** '' for the first command, else ';', '&&' or '||'. */
  op: string;
  text: string;
}

/**
 * Splits `a && b; c || d` into steps, ignoring operators inside quotes. Used by the built-in
 * shell runner, which has no real shell to do it.
 */
export class CommandLine {
  static split(line: string): CommandStep[] {
    const out: CommandStep[] = [];
    let cur = '';
    let quote = '';
    let op = '';
    for (let i = 0; i < line.length; i++) {
      const c = line.charAt(i);
      if (quote.length > 0) {
        cur += c;
        if (c === quote) {
          quote = '';
        } else if (c === '\\' && quote === '"' && i + 1 < line.length) {
          cur += line.charAt(++i);
        }
        continue;
      }
      if (c === '\'' || c === '"') {
        quote = c;
        cur += c;
        continue;
      }
      const two = line.substring(i, i + 2);
      if (two === '&&' || two === '||' || c === ';' || c === '\n') {
        if (cur.trim().length > 0) {
          out.push({ op: op, text: cur.trim() });
        }
        op = two === '&&' || two === '||' ? two : ';';
        cur = '';
        if (two === '&&' || two === '||') {
          i++;
        }
        continue;
      }
      cur += c;
    }
    if (cur.trim().length > 0) {
      out.push({ op: op, text: cur.trim() });
    }
    return out;
  }

  /** Shell features the built-in shell can't do. */
  static unsupportedFeature(line: string): string {
    let quote = '';
    for (let i = 0; i < line.length; i++) {
      const c = line.charAt(i);
      if (quote.length > 0) {
        if (c === quote) {
          quote = '';
        }
        continue;
      }
      if (c === '\'' || c === '"') {
        quote = c;
      } else if (c === '|' && line.charAt(i + 1) !== '|' && (i === 0 || line.charAt(i - 1) !== '|')) {
        return 'pipes (|)';
      } else if (c === '>' || c === '<') {
        return 'redirection (< >)';
      } else if (c === '$' && (line.charAt(i + 1) === '(' || line.charAt(i + 1) === '{')) {
        return 'substitution ($(...))';
      } else if (c === '`') {
        return 'substitution (`...`)';
      }
    }
    return '';
  }
}
