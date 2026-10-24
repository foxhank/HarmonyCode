import { ChangeCode, GitChange, GitStatusRow } from './GitTypes';

// Status-matrix values (see isomorphic-git statusMatrix docs).
const ABSENT: number = 0;
const SAME_AS_HEAD: number = 1;
const CHANGED: number = 2;
const STAGE_DIFFERS: number = 3;

/** Converts git's status matrix into staged / unstaged entries. */
export class GitStatusMapper {
  static toChanges(rows: GitStatusRow[]): GitChange[] {
    const out: GitChange[] = [];
    for (const r of rows) {
      const staged = GitStatusMapper.stagedCode(r);
      const unstaged = GitStatusMapper.unstagedCode(r);
      if (staged.length > 0) {
        out.push({ path: r.path, code: staged, staged: true });
      }
      if (unstaged.length > 0) {
        out.push({ path: r.path, code: unstaged, staged: false });
      }
    }
    return out;
  }

  private static stagedCode(r: GitStatusRow): string {
    const indexHasChange = r.stage === CHANGED || r.stage === STAGE_DIFFERS;
    if (r.head === SAME_AS_HEAD && r.stage === ABSENT) {
      return ChangeCode.DELETED;
    }
    if (r.head === ABSENT && indexHasChange) {
      return ChangeCode.ADDED;
    }
    if (r.head === SAME_AS_HEAD && indexHasChange) {
      return ChangeCode.MODIFIED;
    }
    return '';
  }

  private static unstagedCode(r: GitStatusRow): string {
    if (r.stage === ABSENT && r.workdir !== ABSENT) {
      return ChangeCode.UNTRACKED;
    }
    if (r.workdir === ABSENT && r.stage !== ABSENT) {
      return ChangeCode.DELETED;
    }
    if (r.workdir === CHANGED && (r.stage === SAME_AS_HEAD || r.stage === STAGE_DIFFERS)) {
      return ChangeCode.MODIFIED;
    }
    if (r.workdir === SAME_AS_HEAD && r.stage === STAGE_DIFFERS) {
      return ChangeCode.MODIFIED;
    }
    return '';
  }
}
