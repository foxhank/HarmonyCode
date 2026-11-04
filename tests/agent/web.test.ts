// Live check of the web tools: searches with the key-free providers and fetches a page.
// Usage: node build.mjs web
import { SearchHit, SearchProvider, WebAccess } from '../../entry/src/main/ets/core/agent/web/WebAccess';
import { CancelToken } from '../../entry/src/main/ets/core/llm/CancelToken';
import { NodeHttpTransport } from './NodeHttpTransport';

let failures = 0;
function check(cond: boolean, what: string): void {
  console.log((cond ? '  PASS ' : '  FAIL ') + what);
  if (!cond) {
    failures++;
  }
}

(async () => {
  for (const provider of [SearchProvider.DUCKDUCKGO]) {
    const web = new WebAccess(new NodeHttpTransport(), () => ({ provider: provider, apiKey: '', endpoint: '' }));
    try {
      const hits = await web.search('ArkTS TCPSocket connect HarmonyOS', 8, new CancelToken());
      check(hits.length >= 3 && hits.every((h: SearchHit) => h.url.startsWith('http') && h.title.length > 0),
        `${provider}: ${hits.length} results, e.g. ${hits[0]?.title} <${hits[0]?.url}>`);
    } catch (e) {
      check(false, `${provider}: ${(e as Error).message}`);
    }
  }
  const web = new WebAccess(new NodeHttpTransport(), () => ({ provider: SearchProvider.DUCKDUCKGO, apiKey: '', endpoint: '' }));
  const page = await web.fetch('https://example.com/', new CancelToken());
  check(page.status === 200 && page.title === 'Example Domain' && page.text.includes('documentation examples'), 'fetch + convert: ' + JSON.stringify(page.text.substring(0, 120)));
  console.log(failures === 0 ? '\nALL PASSED' : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
})();
