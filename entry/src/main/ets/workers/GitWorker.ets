// Runs Git operations off the UI thread so clones and status scans don't freeze the editor.
import { worker, MessageEvents, ThreadWorkerGlobalScope } from '@kit.ArkTS';
import {
  GitAuth, gitBranches, gitCheckout, gitClone, gitCommit, gitCreateBranch, gitDiscard, gitFetch, gitInit,
  gitIsRepo, gitLog, gitPull, gitPush, gitReadHead, gitRemotes, gitSetRemote, gitStage, gitStageAll,
  gitStatus, gitUnstage
} from '../vendor/igit';
import { GitOp, GitReplyKind, GitRequest, GitResponse } from '../core/git/GitProtocol';

const port: ThreadWorkerGlobalScope = worker.workerPort;
const NULL_JSON: string = 'null';

function send(r: GitResponse): void {
  port.postMessage(r);
}

function reply(id: number, kind: string, json: string, error: string): void {
  send({ id: id, kind: kind, error: error, json: json, phase: '', loaded: 0, total: 0 });
}

async function run(req: GitRequest): Promise<string> {
  const auth: GitAuth = { username: req.username, token: req.token };
  const onProgress = (phase: string, loaded: number, total: number): void => {
    send({ id: req.id, kind: GitReplyKind.PROGRESS, error: '', json: '', phase: phase, loaded: loaded, total: total });
  };
  switch (req.op) {
    case GitOp.IS_REPO:
      return JSON.stringify(await gitIsRepo(req.dir));
    case GitOp.INIT:
      await gitInit(req.dir, req.a);
      return NULL_JSON;
    case GitOp.STATUS:
      return JSON.stringify(await gitStatus(req.dir));
    case GitOp.STAGE:
      await gitStage(req.dir, req.a);
      return NULL_JSON;
    case GitOp.STAGE_ALL:
      await gitStageAll(req.dir);
      return NULL_JSON;
    case GitOp.UNSTAGE:
      await gitUnstage(req.dir, req.a);
      return NULL_JSON;
    case GitOp.DISCARD:
      await gitDiscard(req.dir, req.a);
      return NULL_JSON;
    case GitOp.COMMIT:
      return JSON.stringify(await gitCommit(req.dir, req.a, req.b, req.c));
    case GitOp.LOG:
      return JSON.stringify(await gitLog(req.dir, req.num));
    case GitOp.BRANCHES:
      return JSON.stringify(await gitBranches(req.dir));
    case GitOp.CREATE_BRANCH:
      await gitCreateBranch(req.dir, req.a, req.flag);
      return NULL_JSON;
    case GitOp.CHECKOUT:
      await gitCheckout(req.dir, req.a);
      return NULL_JSON;
    case GitOp.READ_HEAD:
      return JSON.stringify(await gitReadHead(req.dir, req.a));
    case GitOp.REMOTES:
      return JSON.stringify(await gitRemotes(req.dir));
    case GitOp.SET_REMOTE:
      await gitSetRemote(req.dir, req.a, req.b);
      return NULL_JSON;
    case GitOp.CLONE:
      await gitClone(req.dir, req.a, auth, onProgress);
      return NULL_JSON;
    case GitOp.FETCH:
      return JSON.stringify(await gitFetch(req.dir, auth, onProgress));
    case GitOp.PULL:
      await gitPull(req.dir, auth, req.b, req.c, onProgress);
      return NULL_JSON;
    case GitOp.PUSH:
      await gitPush(req.dir, auth, onProgress);
      return NULL_JSON;
    default:
      throw new Error('Unknown git op: ' + req.op);
  }
}

port.onmessage = (e: MessageEvents): void => {
  const req = e.data as GitRequest;
  run(req).then((json: string) => {
    reply(req.id, GitReplyKind.OK, json, '');
  }).catch((err: Error) => {
    reply(req.id, GitReplyKind.ERROR, '', err?.message ?? String(err));
  });
};
