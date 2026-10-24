import { worker, MessageEvents, ErrorEvent } from '@kit.ArkTS';
import { AppConfig } from '../common/AppConfig';
import { GitOp, GitReplyKind, GitRequest, GitResponse } from './GitProtocol';
import { GitStatusMapper } from './GitStatusMapper';
import {
  GitBranchList, GitChange, GitCommit, GitIdentity, GitProgressFn, GitRemote, GitStatusRow
} from './GitTypes';

class PendingCall {
  resolve: (json: string) => void;
  reject: (e: Error) => void;
  progress: GitProgressFn | undefined;

  constructor(resolve: (json: string) => void, reject: (e: Error) => void, progress: GitProgressFn | undefined) {
    this.resolve = resolve;
    this.reject = reject;
    this.progress = progress;
  }
}

/** Optional arguments for a worker call. */
class CallArgs {
  a: string = '';
  b: string = '';
  c: string = '';
  flag: boolean = false;
  num: number = 0;
  progress: GitProgressFn | undefined = undefined;
}

/**
 * Async Git API. Every call runs in the Git worker (isomorphic-git), so the UI never blocks.
 * Stateless apart from the worker handle; one instance can serve any repository.
 */
export class GitClient {
  private w: worker.ThreadWorker | null = null;
  private seq: number = 0;
  private pending: Map<number, PendingCall> = new Map();
  private identity: GitIdentity;

  constructor(identity: GitIdentity) {
    this.identity = identity;
  }

  async isRepo(dir: string): Promise<boolean> {
    return JSON.parse(await this.call(GitOp.IS_REPO, dir, new CallArgs())) as boolean;
  }

  async init(dir: string): Promise<void> {
    const args = new CallArgs();
    args.a = AppConfig.GIT_DEFAULT_BRANCH;
    await this.call(GitOp.INIT, dir, args);
  }

  async status(dir: string): Promise<GitChange[]> {
    const rows = JSON.parse(await this.call(GitOp.STATUS, dir, new CallArgs())) as GitStatusRow[];
    return GitStatusMapper.toChanges(rows);
  }

  async stage(dir: string, path: string): Promise<void> {
    await this.call(GitOp.STAGE, dir, GitClient.withA(path));
  }

  async stageAll(dir: string): Promise<void> {
    await this.call(GitOp.STAGE_ALL, dir, new CallArgs());
  }

  async unstage(dir: string, path: string): Promise<void> {
    await this.call(GitOp.UNSTAGE, dir, GitClient.withA(path));
  }

  async discard(dir: string, path: string): Promise<void> {
    await this.call(GitOp.DISCARD, dir, GitClient.withA(path));
  }

  /** Returns the new commit id. */
  async commit(dir: string, message: string): Promise<string> {
    const args = GitClient.withA(message);
    args.b = this.identity.authorName();
    args.c = this.identity.authorEmail();
    return JSON.parse(await this.call(GitOp.COMMIT, dir, args)) as string;
  }

  async log(dir: string, depth: number = AppConfig.GIT_LOG_DEPTH): Promise<GitCommit[]> {
    const args = new CallArgs();
    args.num = depth;
    return JSON.parse(await this.call(GitOp.LOG, dir, args)) as GitCommit[];
  }

  async branches(dir: string): Promise<GitBranchList> {
    return JSON.parse(await this.call(GitOp.BRANCHES, dir, new CallArgs())) as GitBranchList;
  }

  async createBranch(dir: string, name: string, checkout: boolean): Promise<void> {
    const args = GitClient.withA(name);
    args.flag = checkout;
    await this.call(GitOp.CREATE_BRANCH, dir, args);
  }

  async checkout(dir: string, ref: string): Promise<void> {
    await this.call(GitOp.CHECKOUT, dir, GitClient.withA(ref));
  }

  /** File content at HEAD ('' if new). */
  async readHead(dir: string, path: string): Promise<string> {
    return JSON.parse(await this.call(GitOp.READ_HEAD, dir, GitClient.withA(path))) as string;
  }

  async remotes(dir: string): Promise<GitRemote[]> {
    return JSON.parse(await this.call(GitOp.REMOTES, dir, new CallArgs())) as GitRemote[];
  }

  async setRemote(dir: string, name: string, url: string): Promise<void> {
    const args = GitClient.withA(name);
    args.b = url;
    await this.call(GitOp.SET_REMOTE, dir, args);
  }

  async clone(dir: string, url: string, progress?: GitProgressFn): Promise<void> {
    const args = GitClient.withA(url);
    args.progress = progress;
    await this.call(GitOp.CLONE, dir, args);
  }

  async fetch(dir: string, progress?: GitProgressFn): Promise<void> {
    const args = new CallArgs();
    args.progress = progress;
    await this.call(GitOp.FETCH, dir, args);
  }

  async pull(dir: string, progress?: GitProgressFn): Promise<void> {
    const args = new CallArgs();
    args.b = this.identity.authorName();
    args.c = this.identity.authorEmail();
    args.progress = progress;
    await this.call(GitOp.PULL, dir, args);
  }

  async push(dir: string, progress?: GitProgressFn): Promise<void> {
    const args = new CallArgs();
    args.progress = progress;
    await this.call(GitOp.PUSH, dir, args);
  }

  /** Stops the worker (it restarts on the next call). */
  dispose(): void {
    if (this.w !== null) {
      this.w.terminate();
      this.w = null;
    }
  }

  private static withA(a: string): CallArgs {
    const args = new CallArgs();
    args.a = a;
    return args;
  }

  private call(op: string, dir: string, args: CallArgs): Promise<string> {
    const id = ++this.seq;
    const req: GitRequest = {
      id: id, op: op, dir: dir, a: args.a, b: args.b, c: args.c, flag: args.flag, num: args.num,
      username: this.identity.username(), token: this.identity.token()
    };
    return new Promise<string>((resolve: (json: string) => void, reject: (e: Error) => void) => {
      this.pending.set(id, new PendingCall(resolve, reject, args.progress));
      this.worker().postMessage(req);
    });
  }

  private worker(): worker.ThreadWorker {
    if (this.w !== null) {
      return this.w;
    }
    const w = new worker.ThreadWorker(AppConfig.GIT_WORKER_PATH);
    w.onmessage = (e: MessageEvents): void => this.onReply(e.data as GitResponse);
    w.onerror = (e: ErrorEvent): void => {
      const err = new Error(e.message);
      this.pending.forEach((p: PendingCall) => p.reject(err));
      this.pending.clear();
      this.w = null;
    };
    this.w = w;
    return w;
  }

  private onReply(r: GitResponse): void {
    const p = this.pending.get(r.id);
    if (p === undefined) {
      return;
    }
    if (r.kind === GitReplyKind.PROGRESS) {
      if (p.progress !== undefined) {
        p.progress(r.phase, r.loaded, r.total);
      }
      return;
    }
    this.pending.delete(r.id);
    if (r.kind === GitReplyKind.OK) {
      p.resolve(r.json);
    } else {
      p.reject(new Error(r.error));
    }
  }
}
