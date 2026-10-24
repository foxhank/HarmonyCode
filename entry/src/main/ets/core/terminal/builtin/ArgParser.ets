/** Splits a command line into words, honouring '…' and "…" quotes and backslash escapes. */
export function tokenize(line: string): string[] {
  const out: string[] = [];
  let cur = '';
  let quote = '';
  let inWord = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line.charAt(i);
    if (quote.length > 0) {
      if (ch === quote) {
        quote = '';
      } else if (ch === '\\' && quote === '"' && i + 1 < line.length) {
        cur += line.charAt(++i);
      } else {
        cur += ch;
      }
      continue;
    }
    if (ch === '"' || ch === '\'') {
      quote = ch;
      inWord = true;
    } else if (ch === '\\' && i + 1 < line.length) {
      cur += line.charAt(++i);
      inWord = true;
    } else if (ch === ' ' || ch === '\t') {
      if (inWord) {
        out.push(cur);
        cur = '';
        inWord = false;
      }
    } else {
      cur += ch;
      inWord = true;
    }
  }
  if (inWord) {
    out.push(cur);
  }
  return out;
}

/** Flags (-a, -rf, --oneline) and positional arguments. */
export class ParsedArgs {
  flags: Set<string> = new Set<string>();
  options: Map<string, string> = new Map<string, string>();
  positional: string[] = [];

  has(flag: string): boolean {
    return this.flags.has(flag);
  }

  option(name: string): string | undefined {
    return this.options.get(name);
  }
}

/**
 * Parses args. `valued` lists flags that take a value (e.g. ['-m', '-n', '-b']).
 * Short flags may be combined (-rf). '--' ends flag parsing.
 */
export function parseArgs(args: string[], valued: string[]): ParsedArgs {
  const p = new ParsedArgs();
  let onlyPositional = false;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (onlyPositional || !a.startsWith('-') || a === '-') {
      p.positional.push(a);
    } else if (a === '--') {
      onlyPositional = true;
    } else if (valued.indexOf(a) >= 0) {
      p.options.set(a, i + 1 < args.length ? args[++i] : '');
    } else if (a.startsWith('--')) {
      p.flags.add(a);
    } else {
      for (let j = 1; j < a.length; j++) {
        p.flags.add('-' + a.charAt(j));
      }
    }
  }
  return p;
}
