/** Change codes shown in Source Control. */
export enum ChangeCode {
  MODIFIED = 'M',
  ADDED = 'A',
  DELETED = 'D',
  UNTRACKED = 'U'
}

/** One file in Source Control. A file can appear twice: once staged, once unstaged. */
export interface GitChange {
  path: string;
  code: string;
  staged: boolean;
}

export interface GitCommit {
  oid: string;
  message: string;
  authorName: string;
  authorEmail: string;
  timestamp: number;
}

export interface GitBranchList {
  current: string;
  local: string[];
  remote: string[];
}

export interface GitRemote {
  remote: string;
  url: string;
}

/** Raw status row from the worker (isomorphic-git status matrix). */
export interface GitStatusRow {
  path: string;
  head: number;
  workdir: number;
  stage: number;
}

export type GitProgressFn = (phase: string, loaded: number, total: number) => void;

/** Who is committing and how to authenticate. Supplied by the app (settings), not read by core directly. */
export interface GitIdentity {
  username(): string;
  token(): string;
  authorName(): string;
  authorEmail(): string;
}
