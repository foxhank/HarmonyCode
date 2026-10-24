/** Operation names understood by the Git worker. */
export class GitOp {
  static readonly IS_REPO: string = 'isRepo';
  static readonly INIT: string = 'init';
  static readonly STATUS: string = 'status';
  static readonly STAGE: string = 'stage';
  static readonly STAGE_ALL: string = 'stageAll';
  static readonly UNSTAGE: string = 'unstage';
  static readonly DISCARD: string = 'discard';
  static readonly COMMIT: string = 'commit';
  static readonly LOG: string = 'log';
  static readonly BRANCHES: string = 'branches';
  static readonly CREATE_BRANCH: string = 'createBranch';
  static readonly CHECKOUT: string = 'checkout';
  static readonly READ_HEAD: string = 'readHead';
  static readonly REMOTES: string = 'remotes';
  static readonly SET_REMOTE: string = 'setRemote';
  static readonly CLONE: string = 'clone';
  static readonly FETCH: string = 'fetch';
  static readonly PULL: string = 'pull';
  static readonly PUSH: string = 'push';
}

export class GitReplyKind {
  static readonly OK: string = 'ok';
  static readonly ERROR: string = 'err';
  static readonly PROGRESS: string = 'progress';
}

/** UI thread -> Git worker. Unused fields are empty. */
export interface GitRequest {
  id: number;
  op: string;
  dir: string;
  a: string;
  b: string;
  c: string;
  flag: boolean;
  num: number;
  username: string;
  token: string;
}

/** Git worker -> UI thread. `json` carries the result for OK replies. */
export interface GitResponse {
  id: number;
  kind: string;
  error: string;
  json: string;
  phase: string;
  loaded: number;
  total: number;
}
