/** Above this many cells (old lines × new lines) the middle of the diff is shown as a block replacement. */
const MAX_LCS_CELLS: number = 4000000;
const CONTEXT_LINES: number = 3;

export class DiffStats {
  added: number = 0;
  removed: number = 0;
}

class Op {
  /** ' ' same, '-' removed, '+' added */
  tag: string;
  text: string;
  oldLine: number;
  newLine: number;

  constructor(tag: string, text: string, oldLine: number, newLine: number) {
    this.tag = tag;
    this.text = text;
    this.oldLine = oldLine;
    this.newLine = newLine;
  }
}

/** Line-based unified diffs, for approval previews and the agent's edit summaries. */
export class LineDiff {
  static split(text: string): string[] {
    if (text.length === 0) {
      return [];
    }
    const lines = text.split('\n');
    if (lines.length > 0 && lines[lines.length - 1] === '') {
      lines.pop();
    }
    return lines;
  }

  static stats(before: string, after: string): DiffStats {
    const s = new DiffStats();
    for (const op of LineDiff.ops(LineDiff.split(before), LineDiff.split(after))) {
      if (op.tag === '+') {
        s.added++;
      } else if (op.tag === '-') {
        s.removed++;
      }
    }
    return s;
  }

  /** Unified diff with `@@` hunk headers and three lines of context; '' when equal. */
  static unified(path: string, before: string, after: string): string {
    const ops = LineDiff.ops(LineDiff.split(before), LineDiff.split(after));
    const changed: number[] = [];
    for (let i = 0; i < ops.length; i++) {
      if (ops[i].tag !== ' ') {
        changed.push(i);
      }
    }
    if (changed.length === 0) {
      return '';
    }
    const out: string[] = ['--- a/' + path, '+++ b/' + path];
    let i = 0;
    while (i < changed.length) {
      const start = Math.max(0, changed[i] - CONTEXT_LINES);
      let end = Math.min(ops.length - 1, changed[i] + CONTEXT_LINES);
      let j = i + 1;
      while (j < changed.length && changed[j] - CONTEXT_LINES <= end + 1) {
        end = Math.min(ops.length - 1, changed[j] + CONTEXT_LINES);
        j++;
      }
      let oldStart = 0;
      let newStart = 0;
      let oldCount = 0;
      let newCount = 0;
      const body: string[] = [];
      for (let k = start; k <= end; k++) {
        const op = ops[k];
        if (op.tag !== '+') {
          oldCount++;
          if (oldStart === 0) {
            oldStart = op.oldLine;
          }
        }
        if (op.tag !== '-') {
          newCount++;
          if (newStart === 0) {
            newStart = op.newLine;
          }
        }
        body.push(op.tag + op.text);
      }
      out.push(`@@ -${oldStart > 0 ? oldStart : ops[start].oldLine},${oldCount} ` +
        `+${newStart > 0 ? newStart : ops[start].newLine},${newCount} @@`);
      for (const b of body) {
        out.push(b);
      }
      i = j;
    }
    return out.join('\n');
  }

  /** Edit script: common prefix/suffix trimmed, LCS in the middle (or a block replace if huge). */
  private static ops(a: string[], b: string[]): Op[] {
    let pre = 0;
    while (pre < a.length && pre < b.length && a[pre] === b[pre]) {
      pre++;
    }
    let suf = 0;
    while (suf < a.length - pre && suf < b.length - pre && a[a.length - 1 - suf] === b[b.length - 1 - suf]) {
      suf++;
    }
    const out: Op[] = [];
    for (let i = 0; i < pre; i++) {
      out.push(new Op(' ', a[i], i + 1, i + 1));
    }
    const am = a.slice(pre, a.length - suf);
    const bm = b.slice(pre, b.length - suf);
    if (am.length * bm.length > MAX_LCS_CELLS) {
      for (let i = 0; i < am.length; i++) {
        out.push(new Op('-', am[i], pre + i + 1, pre + 1));
      }
      for (let i = 0; i < bm.length; i++) {
        out.push(new Op('+', bm[i], pre + am.length + 1, pre + i + 1));
      }
    } else {
      LineDiff.lcs(am, bm, pre, out);
    }
    for (let i = 0; i < suf; i++) {
      const ai = a.length - suf + i;
      const bi = b.length - suf + i;
      out.push(new Op(' ', a[ai], ai + 1, bi + 1));
    }
    return out;
  }

  private static lcs(a: string[], b: string[], offset: number, out: Op[]): void {
    const n = a.length;
    const m = b.length;
    // table[i][j] = LCS length of a[i..] and b[j..], stored row-major.
    const w = m + 1;
    const table = new Int32Array((n + 1) * w);
    for (let i = n - 1; i >= 0; i--) {
      for (let j = m - 1; j >= 0; j--) {
        table[i * w + j] = a[i] === b[j] ? table[(i + 1) * w + j + 1] + 1 :
          Math.max(table[(i + 1) * w + j], table[i * w + j + 1]);
      }
    }
    let i = 0;
    let j = 0;
    while (i < n && j < m) {
      if (a[i] === b[j]) {
        out.push(new Op(' ', a[i], offset + i + 1, offset + j + 1));
        i++;
        j++;
      } else if (table[(i + 1) * w + j] >= table[i * w + j + 1]) {
        out.push(new Op('-', a[i], offset + i + 1, offset + j + 1));
        i++;
      } else {
        out.push(new Op('+', b[j], offset + i + 1, offset + j + 1));
        j++;
      }
    }
    while (i < n) {
      out.push(new Op('-', a[i], offset + i + 1, offset + j + 1));
      i++;
    }
    while (j < m) {
      out.push(new Op('+', b[j], offset + i + 1, offset + j + 1));
      j++;
    }
  }
}
