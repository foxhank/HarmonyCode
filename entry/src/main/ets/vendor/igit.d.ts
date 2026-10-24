// Types for igit.js (built from web/src/git.js by `npm run build` in /web).

export interface GitAuth {
  username: string;
  token: string;
}

/** One changed file from git's status matrix (0 = absent, 1 = same as HEAD, 2/3 = changed). */
export interface GitStatusRow {
  path: string;
  head: number;
  workdir: number;
  stage: number;
}

export interface GitCommitInfo {
  oid: string;
  message: string;
  authorName: string;
  authorEmail: string;
  timestamp: number;
}

export interface GitBranchInfo {
  current: string;
  local: string[];
  remote: string[];
}

export interface GitRemoteInfo {
  remote: string;
  url: string;
}

export type GitProgress = (phase: string, loaded: number, total: number) => void;

export declare function gitIsRepo(dir: string): Promise<boolean>;
export declare function gitInit(dir: string, defaultBranch: string): Promise<void>;
export declare function gitStatus(dir: string): Promise<GitStatusRow[]>;
export declare function gitStage(dir: string, filepath: string): Promise<void>;
export declare function gitStageAll(dir: string): Promise<void>;
export declare function gitUnstage(dir: string, filepath: string): Promise<void>;
export declare function gitDiscard(dir: string, filepath: string): Promise<void>;
export declare function gitCommit(dir: string, message: string, name: string, email: string): Promise<string>;
export declare function gitLog(dir: string, depth: number): Promise<GitCommitInfo[]>;
export declare function gitBranches(dir: string): Promise<GitBranchInfo>;
export declare function gitCreateBranch(dir: string, name: string, checkout: boolean): Promise<void>;
export declare function gitCheckout(dir: string, ref: string): Promise<void>;
export declare function gitReadHead(dir: string, filepath: string): Promise<string>;
export declare function gitRemotes(dir: string): Promise<GitRemoteInfo[]>;
export declare function gitSetRemote(dir: string, remote: string, url: string): Promise<void>;
export declare function gitClone(dir: string, url: string, auth: GitAuth, onProgress: GitProgress): Promise<void>;
export declare function gitFetch(dir: string, auth: GitAuth, onProgress: GitProgress): Promise<string>;
export declare function gitPull(dir: string, auth: GitAuth, name: string, email: string, onProgress: GitProgress): Promise<void>;
export declare function gitPush(dir: string, auth: GitAuth, onProgress: GitProgress): Promise<void>;
