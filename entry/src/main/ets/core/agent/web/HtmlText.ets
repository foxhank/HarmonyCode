/** Elements whose content is never shown. */
const DROP: string[] = ['script', 'style', 'noscript', 'svg', 'template', 'iframe', 'canvas', 'head', 'form', 'nav',
  'footer'];
const BLOCK: string = 'p|div|section|article|main|header|aside|table|tr|ul|ol|dl|blockquote|figure|figcaption|details|summary';
const ENTITIES: Record<string, string> = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': '\'', 'nbsp': ' ', 'mdash': '—', 'ndash': '–',
  'hellip': '…', 'copy': '©', 'reg': '®', 'trade': '™', 'laquo': '«', 'raquo': '»', 'ldquo': '“', 'rdquo': '”',
  'lsquo': '‘', 'rsquo': '’', 'middot': '·', 'bull': '•', 'times': '×'
};

function re(src: string, flags: string = 'gi'): RegExp {
  return new RegExp(src, flags);
}

/**
 * Turns a web page into readable Markdown-like text for the model: drops scripts, styles and
 * navigation, keeps headings, links, lists, code blocks and paragraphs.
 */
export class HtmlText {
  static title(html: string): string {
    const m = re('<title[^>]*>([\\s\\S]*?)</title>', 'i').exec(html);
    return m === null ? '' : HtmlText.decode(m[1]).replace(re('\\s+'), ' ').trim();
  }

  static looksLikeHtml(text: string): boolean {
    const head = text.substring(0, 2000).toLowerCase();
    return head.indexOf('<html') >= 0 || head.indexOf('<!doctype html') >= 0 || head.indexOf('<body') >= 0 ||
      head.indexOf('<head') >= 0;
  }

  static toText(html: string): string {
    let s = html;
    s = s.replace(re('<!--[\\s\\S]*?-->'), '');
    for (const tag of DROP) {
      s = s.replace(re(`<${tag}\\b[^>]*>[\\s\\S]*?</${tag}>`), ' ');
    }
    // Code blocks: keep their text verbatim (protected from whitespace collapsing).
    const blocks: string[] = [];
    s = s.replace(re('<pre\\b[^>]*>([\\s\\S]*?)</pre>'), (m: string, inner: string): string => {
      blocks.push(HtmlText.decode(inner.replace(re('<[^>]+>'), '')));
      return `\n\u0000${blocks.length - 1}\u0000\n`;
    });
    s = s.replace(re('<h([1-6])\\b[^>]*>([\\s\\S]*?)</h\\1>'), (m: string, level: string, inner: string): string => {
      return '\n\n' + '#'.repeat(Number(level)) + ' ' + HtmlText.inline(inner) + '\n\n';
    });
    s = s.replace(re('<a\\b[^>]*?href\\s*=\\s*["\']([^"\']*)["\'][^>]*>([\\s\\S]*?)</a>'),
      (m: string, href: string, inner: string): string => {
        const text = HtmlText.inline(inner);
        if (text.length === 0) {
          return '';
        }
        if (href.startsWith('#') || href.startsWith('javascript:')) {
          return text;
        }
        return `[${text}](${HtmlText.decode(href)})`;
      });
    s = s.replace(re('<code\\b[^>]*>([\\s\\S]*?)</code>'), (m: string, inner: string): string => {
      return '`' + inner.replace(re('<[^>]+>'), '') + '`';
    });
    s = s.replace(re('<(strong|b)\\b[^>]*>([\\s\\S]*?)</\\1>'), '**$2**');
    s = s.replace(re('<li\\b[^>]*>'), '\n- ');
    s = s.replace(re('<(td|th)\\b[^>]*>'), ' | ');
    s = s.replace(re('<br\\s*/?>'), '\n');
    s = s.replace(re('<hr\\b[^>]*>'), '\n---\n');
    s = s.replace(re(`</?(${BLOCK})\\b[^>]*>`), '\n\n');
    s = s.replace(re('<[^>]+>'), '');
    s = HtmlText.decode(s);
    s = s.replace(re('[ \\t\\f\\v\\u00a0]+'), ' ');
    s = s.replace(re(' *\\n *'), '\n');
    s = s.replace(re('\\n{3,}'), '\n\n');
    s = s.replace(re('\\u0000(\\d+)\\u0000'), (m: string, i: string): string => '```\n' + blocks[Number(i)] + '\n```');
    return s.trim();
  }

  private static inline(html: string): string {
    return HtmlText.decode(html.replace(re('<[^>]+>'), '')).replace(re('\\s+'), ' ').trim();
  }

  static decode(s: string): string {
    return s.replace(re('&(#x[0-9a-f]+|#\\d+|[a-z]+);'), (m: string, e: string): string => {
      if (e.startsWith('#x') || e.startsWith('#X')) {
        return HtmlText.fromCode(parseInt(e.substring(2), 16), m);
      }
      if (e.startsWith('#')) {
        return HtmlText.fromCode(parseInt(e.substring(1), 10), m);
      }
      const v = ENTITIES[e.toLowerCase()];
      return v !== undefined ? v : m;
    });
  }

  private static fromCode(code: number, fallback: string): string {
    if (Number.isNaN(code) || code <= 0 || code > 0x10ffff) {
      return fallback;
    }
    return String.fromCodePoint(code);
  }
}
