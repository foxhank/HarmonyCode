// Scoring weights for fuzzy matching.
const CONSECUTIVE: number = 5;
const SINGLE: number = 1;
const WORD_START: number = 3;
const IN_BASENAME: number = 20;
const LENGTH_PENALTY: number = 0.01;
const SEPARATORS: string = '/._-';

export interface Ranked<T> {
  item: T;
  score: number;
}

/** Subsequence matching like VS Code's quick open. */
export class Fuzzy {
  /** Score of `query` against `candidate`; -1 when the letters don't appear in order. */
  static score(query: string, candidate: string): number {
    if (query.length === 0) {
      return 0;
    }
    const q = query.toLowerCase();
    const c = candidate.toLowerCase();
    let qi = 0;
    let score = 0;
    let last = -2;
    for (let i = 0; i < c.length && qi < q.length; i++) {
      if (c.charAt(i) !== q.charAt(qi)) {
        continue;
      }
      score += last === i - 1 ? CONSECUTIVE : SINGLE;
      if (i === 0 || SEPARATORS.indexOf(c.charAt(i - 1)) >= 0) {
        score += WORD_START;
      }
      last = i;
      qi++;
    }
    if (qi < q.length) {
      return -1;
    }
    const base = c.substring(c.lastIndexOf('/') + 1);
    if (base.indexOf(q) >= 0) {
      score += IN_BASENAME;
    }
    return score - c.length * LENGTH_PENALTY;
  }

  /** Best `limit` matches, highest score first. */
  static rank<T>(query: string, items: T[], key: (t: T) => string, limit: number): T[] {
    const ranked: Ranked<T>[] = [];
    for (const it of items) {
      const s = Fuzzy.score(query, key(it));
      if (s >= 0) {
        ranked.push({ item: it, score: s });
      }
    }
    ranked.sort((a: Ranked<T>, b: Ranked<T>) => b.score - a.score);
    return ranked.slice(0, limit).map((r: Ranked<T>) => r.item);
  }
}
