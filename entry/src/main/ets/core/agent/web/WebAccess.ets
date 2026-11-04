import { CancelToken } from '../../llm/CancelToken';
import { HttpBodySink, HttpMethod, HttpRequestSpec, HttpTransport } from '../../llm/HttpTransport';
import { Json, JsonObject } from '../../llm/Json';
import { HtmlText } from './HtmlText';

/** One search result. */
export interface SearchHit {
  title: string;
  url: string;
  snippet: string;
}

/** A fetched page, converted to text when it is HTML. */
export interface WebPage {
  url: string;
  status: number;
  title: string;
  text: string;
}

/** Search back ends. DuckDuckGo needs nothing; Brave and Tavily need an API key; SearXNG needs an instance URL. */
export class SearchProvider {
  static readonly DUCKDUCKGO: string = 'duckduckgo';
  static readonly BRAVE: string = 'brave';
  static readonly TAVILY: string = 'tavily';
  static readonly SEARXNG: string = 'searxng';

  static all(): string[] {
    return [SearchProvider.DUCKDUCKGO, SearchProvider.BRAVE, SearchProvider.TAVILY, SearchProvider.SEARXNG];
  }

  static needsKey(p: string): boolean {
    return p === SearchProvider.BRAVE || p === SearchProvider.TAVILY;
  }

  static needsEndpoint(p: string): boolean {
    return p === SearchProvider.SEARXNG;
  }
}

export interface WebSettings {
  provider: string;
  /** For Brave and Tavily. */
  apiKey: string;
  /** For SearXNG, e.g. "http://192.168.1.10:8888". */
  endpoint: string;
}

const USER_AGENT: string = 'Mozilla/5.0 (Linux; HarmonyOS 5.0) AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/124.0 Mobile Safari/537.36 HarmonyCode';
/** Search pages answer browsers; a plain client gets bot checks or degraded results. */
const DESKTOP_AGENT: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/124.0.0.0 Safari/537.36';
const TIMEOUT_MS: number = 30000;
const CONNECT_TIMEOUT_MS: number = 15000;
const MAX_BODY_CHARS: number = 4 * 1024 * 1024;

class TextSink implements HttpBodySink {
  text: string = '';

  onText(chunk: string): void {
    if (this.text.length < MAX_BODY_CHARS) {
      this.text += chunk;
    }
  }
}

function enc(s: string): string {
  return encodeURIComponent(s);
}

function strip(html: string): string {
  return HtmlText.decode(html.replace(new RegExp('<[^>]+>', 'g'), '')).replace(new RegExp('\\s+', 'g'), ' ').trim();
}

function queryParam(url: string, name: string): string {
  const m = new RegExp('[?&]' + name + '=([^&#]*)').exec(url);
  if (m === null) {
    return '';
  }
  try {
    return decodeURIComponent(m[1].replace(new RegExp('\\+', 'g'), ' '));
  } catch (e) {
    return m[1];
  }
}

/** Web search and page fetching for the agent's web tools. */
export class WebAccess {
  private transport: HttpTransport;
  private settings: () => WebSettings;

  constructor(transport: HttpTransport, settings: () => WebSettings) {
    this.transport = transport;
    this.settings = settings;
  }

  providerName(): string {
    return this.settings().provider;
  }

  async search(query: string, max: number, cancel: CancelToken): Promise<SearchHit[]> {
    const s = this.settings();
    if (SearchProvider.needsKey(s.provider) && s.apiKey.length === 0) {
      throw new Error(`The ${s.provider} search provider needs an API key (Settings > Agent > Web search).`);
    }
    if (SearchProvider.needsEndpoint(s.provider) && s.endpoint.trim().length === 0) {
      throw new Error('SearXNG needs the address of your instance (Settings > Agent > Web search).');
    }
    let hits: SearchHit[];
    if (s.provider === SearchProvider.BRAVE) {
      hits = await this.brave(query, max, s.apiKey, cancel);
    } else if (s.provider === SearchProvider.TAVILY) {
      hits = await this.tavily(query, max, s.apiKey, cancel);
    } else if (s.provider === SearchProvider.SEARXNG) {
      hits = await this.searxng(query, s.endpoint, cancel);
    } else {
      hits = await this.duckduckgo(query, cancel);
    }
    return hits.filter((h: SearchHit) => h.url.startsWith('http')).slice(0, max);
  }

  async fetch(url: string, cancel: CancelToken): Promise<WebPage> {
    const r = await this.request(HttpMethod.GET, url, '', {
      'User-Agent': USER_AGENT, 'Accept': 'text/html,application/xhtml+xml,text/plain,application/json;q=0.9,*/*;q=0.5'
    }, cancel);
    if (r.text.indexOf('\u0000') >= 0) {
      throw new Error('The URL returned binary content, not text.');
    }
    if (HtmlText.looksLikeHtml(r.text)) {
      return { url: url, status: r.status, title: HtmlText.title(r.text), text: HtmlText.toText(r.text) };
    }
    return { url: url, status: r.status, title: '', text: r.text };
  }

  // ---------- providers ----------

  private async duckduckgo(query: string, cancel: CancelToken): Promise<SearchHit[]> {
    const r = await this.request(HttpMethod.GET, 'https://html.duckduckgo.com/html/?q=' + enc(query), '', {
      'User-Agent': DESKTOP_AGENT, 'Accept': 'text/html,application/xhtml+xml', 'Accept-Language': 'en-US,en;q=0.9'
    }, cancel);
    if (r.status === 202) {
      throw new Error('DuckDuckGo asked for a bot check. Try again later or switch to another search provider.');
    }
    WebAccess.checkStatus(r.status, 'DuckDuckGo');
    const out: SearchHit[] = [];
    const blocks = r.text.split(new RegExp('<div class="result results_links', 'i'));
    for (let i = 1; i < blocks.length; i++) {
      const b = blocks[i];
      // The rest of the class attribute marks ads.
      if (b.substring(0, 80).indexOf('result--ad') >= 0) {
        continue;
      }
      const a = new RegExp('<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>([\\s\\S]*?)</a>', 'i').exec(b);
      if (a === null) {
        continue;
      }
      let url = HtmlText.decode(a[1]);
      const real = queryParam(url, 'uddg');
      if (real.length > 0) {
        url = real;
      } else if (url.startsWith('//')) {
        url = 'https:' + url;
      }
      const sn = new RegExp('class="result__snippet"[^>]*>([\\s\\S]*?)</a>', 'i').exec(b);
      out.push({ title: strip(a[2]), url: url, snippet: sn !== null ? strip(sn[1]) : '' });
    }
    return out;
  }

  private async brave(query: string, max: number, key: string, cancel: CancelToken): Promise<SearchHit[]> {
    const r = await this.request(HttpMethod.GET, 'https://api.search.brave.com/res/v1/web/search?q=' + enc(query) +
      '&count=' + Math.min(20, max), '', { 'Accept': 'application/json', 'X-Subscription-Token': key }, cancel);
    WebAccess.checkStatus(r.status, 'Brave');
    const body = Json.parseObject(r.text);
    const results = Json.arr(Json.obj(body, 'web'), 'results');
    return results.map((v: Object): SearchHit => {
      const o = Json.asObject(v);
      return { title: strip(Json.str(o, 'title')), url: Json.str(o, 'url'), snippet: strip(Json.str(o, 'description')) };
    });
  }

  private async tavily(query: string, max: number, key: string, cancel: CancelToken): Promise<SearchHit[]> {
    const payload: JsonObject = { 'query': query, 'max_results': Math.min(20, max) };
    const r = await this.request(HttpMethod.POST, 'https://api.tavily.com/search', JSON.stringify(payload), {
      'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key
    }, cancel);
    WebAccess.checkStatus(r.status, 'Tavily');
    const results = Json.arr(Json.parseObject(r.text), 'results');
    return results.map((v: Object): SearchHit => {
      const o = Json.asObject(v);
      return { title: Json.str(o, 'title'), url: Json.str(o, 'url'), snippet: Json.str(o, 'content') };
    });
  }

  /** A SearXNG instance's JSON API (the instance must allow format=json). */
  private async searxng(query: string, endpoint: string, cancel: CancelToken): Promise<SearchHit[]> {
    const base = endpoint.trim().replace(new RegExp('/+$'), '');
    const r = await this.request(HttpMethod.GET, base + '/search?format=json&q=' + enc(query), '',
      { 'Accept': 'application/json' }, cancel);
    if (r.status === 403) {
      throw new Error('The SearXNG instance refused JSON output; add "json" to search.formats in its settings.yml.');
    }
    WebAccess.checkStatus(r.status, 'SearXNG');
    return Json.arr(Json.parseObject(r.text), 'results').map((v: Object): SearchHit => {
      const o = Json.asObject(v);
      return { title: Json.str(o, 'title'), url: Json.str(o, 'url'), snippet: Json.str(o, 'content') };
    });
  }

  private static checkStatus(status: number, who: string): void {
    if (status === 401 || status === 403) {
      throw new Error(`${who} refused the request (HTTP ${status}); check the API key or try another provider.`);
    }
    if (status < 200 || status >= 300) {
      throw new Error(`${who} search failed with HTTP ${status}.`);
    }
  }

  private async request(method: string, url: string, body: string, headers: Record<string, string>,
    cancel: CancelToken): Promise<RawResponse> {
    const spec: HttpRequestSpec = {
      method: method, url: url, headers: headers, body: body, timeoutMs: TIMEOUT_MS, connectTimeoutMs: CONNECT_TIMEOUT_MS
    };
    const sink = new TextSink();
    const status = await this.transport.send(spec, sink, cancel);
    return { status: status, text: sink.text };
  }
}

interface RawResponse {
  status: number;
  text: string;
}
