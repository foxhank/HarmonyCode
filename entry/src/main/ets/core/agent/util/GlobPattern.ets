/**
 * Glob matching for project-relative paths: `*` (within a segment), `**` (any depth), `?`,
 * `[abc]` classes and `{a,b}` alternatives. A pattern without '/' matches the file name at any depth.
 */
export class GlobPattern {
  private re: RegExp;
  readonly source: string;

  constructor(pattern: string) {
    let p = pattern.trim().replace(new RegExp('\\\\', 'g'), '/');
    if (p.startsWith('./')) {
      p = p.substring(2);
    }
    if (p.indexOf('/') < 0) {
      p = '**/' + p;
    }
    this.source = p;
    this.re = new RegExp('^' + GlobPattern.toRegex(p) + '$');
  }

  matches(relPath: string): boolean {
    return this.re.test(relPath);
  }

  private static toRegex(p: string): string {
    let out = '';
    let inGroup = 0;
    for (let i = 0; i < p.length; i++) {
      const c = p.charAt(i);
      if (c === '*') {
        if (p.charAt(i + 1) === '*') {
          // '**/' = zero or more folders; a trailing '**' = everything below.
          if (p.charAt(i + 2) === '/') {
            out += '(?:.*/)?';
            i += 2;
          } else {
            out += '.*';
            i += 1;
          }
        } else {
          out += '[^/]*';
        }
      } else if (c === '?') {
        out += '[^/]';
      } else if (c === '[') {
        const close = p.indexOf(']', i + 1);
        if (close < 0) {
          out += '\\[';
        } else {
          let cls = p.substring(i + 1, close);
          if (cls.startsWith('!')) {
            cls = '^' + cls.substring(1);
          }
          out += '[' + cls.replace(new RegExp('\\\\', 'g'), '\\\\') + ']';
          i = close;
        }
      } else if (c === '{') {
        inGroup++;
        out += '(?:';
      } else if (c === '}' && inGroup > 0) {
        inGroup--;
        out += ')';
      } else if (c === ',' && inGroup > 0) {
        out += '|';
      } else if ('.+^$()|\\'.indexOf(c) >= 0) {
        out += '\\' + c;
      } else {
        out += c;
      }
    }
    return out;
  }
}
