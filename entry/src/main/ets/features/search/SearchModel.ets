import { AppConfig } from '../../core/common/AppConfig';
import { SearchHit, SearchOptions, TextSearch } from '../../core/search/TextSearch';

/** Hits grouped by file, for the results tree. */
export interface SearchGroup {
  path: string;
  relPath: string;
  hits: SearchHit[];
}

const DEBOUNCE_MS: number = 300;

/** Find in files. */
@ObservedV2
export class SearchModel {
  @Trace query: string = '';
  @Trace matchCase: boolean = false;
  @Trace regex: boolean = false;
  @Trace groups: SearchGroup[] = [];
  @Trace total: number = 0;
  @Trace busy: boolean = false;
  @Trace invalid: boolean = false;
  private root: string;
  private timer: number = -1;
  private openHit: (hit: SearchHit) => void;

  constructor(root: string, openHit: (hit: SearchHit) => void) {
    this.root = root;
    this.openHit = openHit;
  }

  setQuery(q: string): void {
    this.query = q;
    this.schedule();
  }

  toggleCase(): void {
    this.matchCase = !this.matchCase;
    this.schedule();
  }

  toggleRegex(): void {
    this.regex = !this.regex;
    this.schedule();
  }

  open(hit: SearchHit): void {
    this.openHit(hit);
  }

  /** Runs now (e.g. on Enter). */
  run(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    const opts: SearchOptions = { matchCase: this.matchCase, regex: this.regex, limit: AppConfig.SEARCH_MAX_RESULTS };
    this.invalid = this.query.length > 0 && TextSearch.compile(this.query, opts) === null;
    if (this.query.length === 0 || this.invalid) {
      this.groups = [];
      this.total = 0;
      return;
    }
    this.busy = true;
    // Yield one frame so the busy indicator shows before the (synchronous) scan.
    setTimeout(() => {
      const hits = TextSearch.run(this.root, this.query, opts);
      const byFile = new Map<string, SearchGroup>();
      for (const h of hits) {
        let g = byFile.get(h.path);
        if (g === undefined) {
          g = { path: h.path, relPath: h.relPath, hits: [] };
          byFile.set(h.path, g);
        }
        g.hits.push(h);
      }
      this.groups = Array.from(byFile.values());
      this.total = hits.length;
      this.busy = false;
    }, 0);
  }

  private schedule(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
    }
    this.timer = setTimeout(() => {
      this.timer = -1;
      this.run();
    }, DEBOUNCE_MS);
  }
}
