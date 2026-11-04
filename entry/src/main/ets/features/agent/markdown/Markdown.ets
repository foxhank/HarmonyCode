/** Inline styles. */
export class SpanKind {
  static readonly TEXT: string = 'text';
  static readonly BOLD: string = 'bold';
  static readonly ITALIC: string = 'italic';
  static readonly CODE: string = 'code';
  static readonly LINK: string = 'link';
}

export class MdSpan {
  kind: string;
  text: string;

  constructor(kind: string, text: string) {
    this.kind = kind;
    this.text = text;
  }
}

export class BlockKind {
  static readonly PARAGRAPH: string = 'p';
  static readonly HEADING: string = 'h';
  static readonly LIST_ITEM: string = 'li';
  static readonly CODE: string = 'code';
  static readonly QUOTE: string = 'quote';
  static readonly RULE: string = 'hr';
}

export class MdBlock {
  kind: string;
  spans: MdSpan[] = [];
  /** HEADING: 1-6. LIST_ITEM: nesting depth (0 = top). */
  level: number = 0;
  /** LIST_ITEM: "•" or "3." */
  marker: string = '';
  /** CODE: language and raw text. */
  lang: string = '';
  code: string = '';

  constructor(kind: string) {
    this.kind = kind;
  }
}

const FENCE: RegExp = new RegExp('^\\s*(```|~~~)(.*)$');
const HEADING: RegExp = new RegExp('^(#{1,6})\\s+(.*)$');
const BULLET: RegExp = new RegExp('^(\\s*)[-*+]\\s+(.*)$');
const ORDERED: RegExp = new RegExp('^(\\s*)(\\d+)[.)]\\s+(.*)$');
const RULE: RegExp = new RegExp('^\\s*([-*_])(\\s*\\1){2,}\\s*$');
const QUOTE: RegExp = new RegExp('^\\s*>\\s?(.*)$');
const INDENT_PER_LEVEL: number = 2;

/**
 * Small Markdown parser for agent replies: headings, paragraphs, bullet and numbered lists,
 * fenced code, quotes, rules, and inline code / bold / italic / links. An unclosed fence (while
 * streaming) is shown as code up to the end.
 */
export class Markdown {
  static parse(text: string): MdBlock[] {
    const blocks: MdBlock[] = [];
    const lines = text.replace(new RegExp('\\r\\n', 'g'), '\n').split('\n');
    let para: string[] = [];
    const flushPara = (): void => {
      if (para.length > 0) {
        const b = new MdBlock(BlockKind.PARAGRAPH);
        b.spans = Markdown.inline(para.join('\n'));
        blocks.push(b);
        para = [];
      }
    };
    let i = 0;
    while (i < lines.length) {
      const line = lines[i];
      const fence = FENCE.exec(line);
      if (fence !== null) {
        flushPara();
        const b = new MdBlock(BlockKind.CODE);
        b.lang = fence[2].trim();
        const body: string[] = [];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith(fence[1])) {
          body.push(lines[i]);
          i++;
        }
        b.code = body.join('\n');
        blocks.push(b);
        i++;
        continue;
      }
      if (line.trim().length === 0) {
        flushPara();
        i++;
        continue;
      }
      const h = HEADING.exec(line);
      if (h !== null) {
        flushPara();
        const b = new MdBlock(BlockKind.HEADING);
        b.level = h[1].length;
        b.spans = Markdown.inline(h[2].trim());
        blocks.push(b);
        i++;
        continue;
      }
      if (RULE.test(line)) {
        flushPara();
        blocks.push(new MdBlock(BlockKind.RULE));
        i++;
        continue;
      }
      const bullet = BULLET.exec(line);
      const ordered = bullet === null ? ORDERED.exec(line) : null;
      if (bullet !== null || ordered !== null) {
        flushPara();
        const b = new MdBlock(BlockKind.LIST_ITEM);
        const indent = bullet !== null ? bullet[1] : (ordered as RegExpExecArray)[1];
        b.level = Math.floor(indent.replace(new RegExp('\\t', 'g'), '  ').length / INDENT_PER_LEVEL);
        b.marker = bullet !== null ? '•' : (ordered as RegExpExecArray)[2] + '.';
        let content = bullet !== null ? bullet[2] : (ordered as RegExpExecArray)[3];
        // Continuation lines of the same item.
        while (i + 1 < lines.length && lines[i + 1].startsWith('  ') && lines[i + 1].trim().length > 0 &&
          !BULLET.test(lines[i + 1]) && !ORDERED.test(lines[i + 1]) && FENCE.exec(lines[i + 1]) === null) {
          i++;
          content += ' ' + lines[i].trim();
        }
        b.spans = Markdown.inline(content);
        blocks.push(b);
        i++;
        continue;
      }
      const q = QUOTE.exec(line);
      if (q !== null) {
        flushPara();
        const quoted: string[] = [q[1]];
        while (i + 1 < lines.length && QUOTE.test(lines[i + 1])) {
          i++;
          quoted.push((QUOTE.exec(lines[i]) as RegExpExecArray)[1]);
        }
        const b = new MdBlock(BlockKind.QUOTE);
        b.spans = Markdown.inline(quoted.join('\n'));
        blocks.push(b);
        i++;
        continue;
      }
      para.push(line);
      i++;
    }
    flushPara();
    return blocks;
  }

  /** Inline formatting: `code`, **bold**, __bold__, *italic*, _italic_, [text](url). */
  static inline(text: string): MdSpan[] {
    const out: MdSpan[] = [];
    let buf = '';
    const push = (kind: string, t: string): void => {
      if (buf.length > 0) {
        out.push(new MdSpan(SpanKind.TEXT, buf));
        buf = '';
      }
      if (t.length > 0) {
        out.push(new MdSpan(kind, t));
      }
    };
    let i = 0;
    while (i < text.length) {
      const c = text.charAt(i);
      if (c === '\\' && i + 1 < text.length && '\\`*_[]()#'.indexOf(text.charAt(i + 1)) >= 0) {
        buf += text.charAt(i + 1);
        i += 2;
        continue;
      }
      if (c === '`') {
        const end = text.indexOf('`', i + 1);
        if (end > i) {
          push(SpanKind.CODE, text.substring(i + 1, end));
          i = end + 1;
          continue;
        }
      }
      const two = text.substring(i, i + 2);
      if (two === '**' || two === '__') {
        const end = text.indexOf(two, i + 2);
        if (end > i + 2) {
          push(SpanKind.BOLD, Markdown.plain(text.substring(i + 2, end)));
          i = end + 2;
          continue;
        }
      }
      if ((c === '*' || c === '_') && i + 1 < text.length && text.charAt(i + 1) !== ' ') {
        const end = text.indexOf(c, i + 1);
        const wordStart = i === 0 || ' \n('.indexOf(text.charAt(i - 1)) >= 0;
        if (end > i + 1 && wordStart && text.charAt(end - 1) !== ' ') {
          push(SpanKind.ITALIC, text.substring(i + 1, end));
          i = end + 1;
          continue;
        }
      }
      if (c === '[') {
        const close = text.indexOf('](', i);
        const end = close > i ? text.indexOf(')', close) : -1;
        if (close > i && end > close) {
          push(SpanKind.LINK, text.substring(i + 1, close));
          i = end + 1;
          continue;
        }
      }
      buf += c;
      i++;
    }
    push(SpanKind.TEXT, '');
    return out;
  }

  /** Text without inline markers (for bold content). */
  private static plain(text: string): string {
    return text.replace(new RegExp('`', 'g'), '');
  }
}
