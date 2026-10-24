import { AppConfig } from '../common/AppConfig';
import { FileService } from '../fs/FileService';
import { PathUtil } from '../fs/PathUtil';

export interface SearchHit {
  path: string;
  relPath: string;
  line: number;
  col: number;
  preview: string;
}

export interface SearchOptions {
  matchCase: boolean;
  regex: boolean;
  limit: number;
}

const ELLIPSIS: string = '…';

/** Text / regex search across a project. Skips binaries, large files and ignored folders. */
export class TextSearch {
  static escapeRegExp(s: string): string {
    return s.replace(new RegExp('[.*+?^${}()|[\\]\\\\]', 'g'), '\\$&');
  }

  /** Returns null when `query` is not a valid regular expression. */
  static compile(query: string, opts: SearchOptions): RegExp | null {
    try {
      return new RegExp(opts.regex ? query : TextSearch.escapeRegExp(query), opts.matchCase ? '' : 'i');
    } catch (e) {
      return null;
    }
  }

  static run(root: string, query: string, opts: SearchOptions): SearchHit[] {
    const hits: SearchHit[] = [];
    const re = query.length > 0 ? TextSearch.compile(query, opts) : null;
    if (re === null) {
      return hits;
    }
    for (const f of FileService.walk(root, AppConfig.SEARCH_MAX_FILES)) {
      if (FileService.size(f) > AppConfig.SEARCH_MAX_FILE_BYTES) {
        continue;
      }
      let text = '';
      try {
        text = FileService.readText(f);
      } catch (e) {
        continue; // binary or unreadable
      }
      const lines = text.split('\n');
      for (let i = 0; i < lines.length; i++) {
        const m = re.exec(lines[i]);
        if (m === null) {
          continue;
        }
        const start = Math.max(0, m.index - AppConfig.SEARCH_PREVIEW_LEAD);
        hits.push({
          path: f, relPath: PathUtil.relative(root, f), line: i + 1, col: m.index + 1,
          preview: (start > 0 ? ELLIPSIS : '') + lines[i].substring(start, start + AppConfig.SEARCH_PREVIEW_LEN).trim()
        });
        if (hits.length >= opts.limit) {
          return hits;
        }
      }
    }
    return hits;
  }
}
