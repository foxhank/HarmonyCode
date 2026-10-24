import { Strings } from '../../common/Strings';
import { AppConfig } from '../../common/AppConfig';
import { errorMessage } from '../../common/Logger';
import { FileService } from '../../fs/FileService';
import { PathUtil } from '../../fs/PathUtil';
import { ProjectFactory } from '../../project/ProjectFactory';
import { ChangeCode, GitChange, GitCommit } from '../../git/GitTypes';
import { Ansi } from '../Ansi';
import { parseArgs } from './ArgParser';
import { Exit, FnCommand, ShellCommand, ShellContext } from './ShellCommand';

const SHORT_OID: number = 7;
const PERCENT: number = 100;

type GitSub = (ctx: ShellContext, args: string[]) => Promise<number>;

function codeLabel(code: string): string {
  switch (code) {
    case ChangeCode.MODIFIED:
      return Strings.get('git_label_modified');
    case ChangeCode.ADDED:
      return Strings.get('git_label_added');
    case ChangeCode.DELETED:
      return Strings.get('git_label_deleted');
    default:
      return Strings.get('git_label_untracked');
  }
}

/** Repository root for git commands: always the project folder. */
function repo(ctx: ShellContext): string {
  return ctx.home();
}

/** Path relative to the repo for a user-typed path. */
function repoPath(ctx: ShellContext, input: string): string {
  return PathUtil.relative(repo(ctx), ctx.resolve(input));
}

function progressPrinter(ctx: ShellContext): (phase: string, loaded: number, total: number) => void {
  return (phase: string, loaded: number, total: number): void => {
    const pct = total > 0 ? ' ' + Math.floor(loaded * PERCENT / total) + '%' : '';
    ctx.io.write('\r' + Ansi.dim(phase + pct) + Ansi.CLEAR_LINE_RIGHT);
  };
}

async function status(ctx: ShellContext, args: string[]): Promise<number> {
  const branches = await ctx.git.branches(repo(ctx));
  ctx.io.writeln(Strings.get('git_on_branch', branches.current));
  const changes = await ctx.git.status(repo(ctx));
  if (changes.length === 0) {
    ctx.io.writeln(Strings.get('git_clean'));
    return Exit.OK;
  }
  const staged = changes.filter((c: GitChange) => c.staged);
  const unstaged = changes.filter((c: GitChange) => !c.staged && c.code !== ChangeCode.UNTRACKED);
  const untracked = changes.filter((c: GitChange) => c.code === ChangeCode.UNTRACKED);
  if (staged.length > 0) {
    ctx.io.writeln(Strings.get('git_section_staged'));
    for (const c of staged) {
      ctx.io.writeln('\t' + Ansi.green(codeLabel(c.code) + ':   ' + c.path));
    }
  }
  if (unstaged.length > 0) {
    ctx.io.writeln(Strings.get('git_section_unstaged'));
    for (const c of unstaged) {
      ctx.io.writeln('\t' + Ansi.red(codeLabel(c.code) + ':   ' + c.path));
    }
  }
  if (untracked.length > 0) {
    ctx.io.writeln(Strings.get('git_section_untracked'));
    for (const c of untracked) {
      ctx.io.writeln('\t' + Ansi.red(c.path));
    }
  }
  return Exit.OK;
}

async function add(ctx: ShellContext, args: string[]): Promise<number> {
  const p = parseArgs(args, []);
  if (p.has('-A') || p.has('--all') || p.positional.indexOf('.') >= 0) {
    await ctx.git.stageAll(repo(ctx));
  } else if (p.positional.length === 0) {
    ctx.io.error(Strings.get('git_add_nothing'));
    return Exit.USAGE;
  } else {
    for (const f of p.positional) {
      await ctx.git.stage(repo(ctx), repoPath(ctx, f));
    }
  }
  ctx.host.gitChanged();
  return Exit.OK;
}

async function reset(ctx: ShellContext, args: string[]): Promise<number> {
  const p = parseArgs(args, []);
  for (const f of p.positional) {
    await ctx.git.unstage(repo(ctx), repoPath(ctx, f));
  }
  ctx.host.gitChanged();
  return Exit.OK;
}

async function restore(ctx: ShellContext, args: string[]): Promise<number> {
  const p = parseArgs(args, []);
  for (const f of p.positional) {
    if (p.has('--staged')) {
      await ctx.git.unstage(repo(ctx), repoPath(ctx, f));
    } else {
      await ctx.git.discard(repo(ctx), repoPath(ctx, f));
    }
  }
  ctx.host.gitChanged();
  ctx.host.filesChanged('');
  return Exit.OK;
}

async function commit(ctx: ShellContext, args: string[]): Promise<number> {
  const p = parseArgs(args, ['-m']);
  const msg = p.option('-m') ?? '';
  if (msg.trim().length === 0) {
    ctx.io.error(Strings.get('git_commit_need_message'));
    return Exit.USAGE;
  }
  if (p.has('-a')) {
    await ctx.git.stageAll(repo(ctx));
  }
  const oid = await ctx.git.commit(repo(ctx), msg);
  const branches = await ctx.git.branches(repo(ctx));
  ctx.io.writeln('[' + branches.current + ' ' + oid.substring(0, SHORT_OID) + '] ' + msg.split('\n')[0]);
  ctx.host.gitChanged();
  return Exit.OK;
}

async function log(ctx: ShellContext, args: string[]): Promise<number> {
  const p = parseArgs(args, ['-n']);
  const depth = Number(p.option('-n') ?? AppConfig.GIT_LOG_DEPTH);
  const commits = await ctx.git.log(repo(ctx), depth);
  for (const c of commits) {
    if (p.has('--oneline')) {
      ctx.io.writeln(Ansi.yellow(c.oid.substring(0, SHORT_OID)) + ' ' + c.message.split('\n')[0]);
    } else {
      ctx.io.writeln(Ansi.yellow(Strings.get('git_log_commit', c.oid)));
      ctx.io.writeln(Strings.get('git_log_author', c.authorName, c.authorEmail));
      ctx.io.writeln(Strings.get('git_log_date', new Date(c.timestamp * 1000).toLocaleString()));
      ctx.io.writeln('');
      for (const line of c.message.trimEnd().split('\n')) {
        ctx.io.writeln('    ' + line);
      }
      ctx.io.writeln('');
    }
  }
  return Exit.OK;
}

async function branch(ctx: ShellContext, args: string[]): Promise<number> {
  const p = parseArgs(args, []);
  if (p.positional.length > 0) {
    await ctx.git.createBranch(repo(ctx), p.positional[0], false);
    return Exit.OK;
  }
  const b = await ctx.git.branches(repo(ctx));
  for (const name of b.local) {
    ctx.io.writeln(name === b.current ? '* ' + Ansi.green(name) : '  ' + name);
  }
  if (p.has('-a')) {
    for (const name of b.remote) {
      ctx.io.writeln('  ' + Ansi.red('remotes/origin/' + name));
    }
  }
  return Exit.OK;
}

async function checkout(ctx: ShellContext, args: string[]): Promise<number> {
  const p = parseArgs(args, ['-b', '-c']);
  const newBranch = p.option('-b') ?? p.option('-c');
  if (newBranch !== undefined) {
    await ctx.git.createBranch(repo(ctx), newBranch, true);
    ctx.io.writeln(Strings.get('git_switched_new', newBranch));
  } else if (p.positional.length > 0) {
    await ctx.git.checkout(repo(ctx), p.positional[0]);
    ctx.io.writeln(Strings.get('git_switched', p.positional[0]));
  } else {
    ctx.io.error(Strings.get('sh_err_missing_operand', 'git checkout'));
    return Exit.USAGE;
  }
  ctx.host.gitChanged();
  ctx.host.filesChanged('');
  return Exit.OK;
}

async function init(ctx: ShellContext, args: string[]): Promise<number> {
  await ctx.git.init(repo(ctx));
  ctx.io.writeln(Strings.get('git_init_done', ctx.display(repo(ctx))));
  ctx.host.gitChanged();
  return Exit.OK;
}

async function clone(ctx: ShellContext, args: string[]): Promise<number> {
  const p = parseArgs(args, []);
  if (p.positional.length === 0) {
    ctx.io.error(Strings.get('sh_err_missing_operand', 'git clone'));
    return Exit.USAGE;
  }
  const url = p.positional[0];
  const dir = ctx.resolve(p.positional.length > 1 ? p.positional[1] : ProjectFactory.nameFromUrl(url));
  if (FileService.exists(dir) && FileService.list(dir).length > 0) {
    ctx.io.error(Strings.get('git_clone_exists', ctx.display(dir)));
    return Exit.FAIL;
  }
  ctx.io.writeln(Strings.get('git_cloning', ctx.display(dir)));
  FileService.mkdirs(dir);
  await ctx.git.clone(dir, url, progressPrinter(ctx));
  ctx.io.writeln('\r' + Ansi.CLEAR_LINE_RIGHT + Strings.get('git_done'));
  ctx.host.filesChanged('');
  return Exit.OK;
}

async function pull(ctx: ShellContext, args: string[]): Promise<number> {
  await ctx.git.pull(repo(ctx), progressPrinter(ctx));
  ctx.io.writeln('\r' + Ansi.CLEAR_LINE_RIGHT + Strings.get('git_done'));
  ctx.host.gitChanged();
  ctx.host.filesChanged('');
  return Exit.OK;
}

async function push(ctx: ShellContext, args: string[]): Promise<number> {
  await ctx.git.push(repo(ctx), progressPrinter(ctx));
  ctx.io.writeln('\r' + Ansi.CLEAR_LINE_RIGHT + Strings.get('git_done'));
  ctx.host.gitChanged();
  return Exit.OK;
}

async function fetch(ctx: ShellContext, args: string[]): Promise<number> {
  await ctx.git.fetch(repo(ctx), progressPrinter(ctx));
  ctx.io.writeln('\r' + Ansi.CLEAR_LINE_RIGHT + Strings.get('git_done'));
  ctx.host.gitChanged();
  return Exit.OK;
}

async function remote(ctx: ShellContext, args: string[]): Promise<number> {
  const p = parseArgs(args, []);
  if (p.positional[0] === 'add' || p.positional[0] === 'set-url') {
    if (p.positional.length < 3) {
      ctx.io.error(Strings.get('sh_err_missing_operand', 'git remote ' + p.positional[0]));
      return Exit.USAGE;
    }
    await ctx.git.setRemote(repo(ctx), p.positional[1], p.positional[2]);
    ctx.host.gitChanged();
    return Exit.OK;
  }
  for (const r of await ctx.git.remotes(repo(ctx))) {
    ctx.io.writeln(p.has('-v') ? r.remote + '\t' + r.url : r.remote);
  }
  return Exit.OK;
}

const SUBCOMMANDS: Map<string, GitSub> = new Map<string, GitSub>([
  ['status', status], ['add', add], ['reset', reset], ['restore', restore], ['commit', commit], ['log', log],
  ['branch', branch], ['checkout', checkout], ['switch', checkout], ['init', init], ['clone', clone],
  ['pull', pull], ['push', push], ['fetch', fetch], ['remote', remote],
]);

async function git(ctx: ShellContext, args: string[]): Promise<number> {
  const sub = args.length > 0 ? SUBCOMMANDS.get(args[0]) : undefined;
  if (sub === undefined) {
    ctx.io.writeln(Strings.get('git_usage', Array.from(SUBCOMMANDS.keys()).join(', ')));
    return args.length === 0 ? Exit.OK : Exit.USAGE;
  }
  const needsRepo = args[0] !== 'init' && args[0] !== 'clone';
  if (needsRepo && !(await ctx.git.isRepo(repo(ctx)))) {
    ctx.io.error(Strings.get('git_not_repo'));
    return Exit.FAIL;
  }
  try {
    return await sub(ctx, args.slice(1));
  } catch (e) {
    ctx.io.write('\r' + Ansi.CLEAR_LINE_RIGHT);
    ctx.io.error(Strings.get('git_error', errorMessage(e as Error)));
    return Exit.FAIL;
  }
}

export function gitCommands(): ShellCommand[] {
  return [new FnCommand('git', 'sh_help_git', git)];
}

/** Shown in `git log` style lists elsewhere. */
export function shortOid(c: GitCommit): string {
  return c.oid.substring(0, SHORT_OID);
}
