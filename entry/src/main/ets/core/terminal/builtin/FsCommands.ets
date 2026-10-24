import { Strings } from '../../common/Strings';
import { errorMessage } from '../../common/Logger';
import { FileService } from '../../fs/FileService';
import { PathUtil } from '../../fs/PathUtil';
import { Ansi } from '../Ansi';
import { parseArgs } from './ArgParser';
import { Exit, FnCommand, ShellCommand, ShellContext } from './ShellCommand';

async function ls(ctx: ShellContext, args: string[]): Promise<number> {
  const p = parseArgs(args, []);
  const targets = p.positional.length > 0 ? p.positional : ['.'];
  let code = Exit.OK;
  for (const t of targets) {
    const path = ctx.resolve(t);
    if (!FileService.exists(path)) {
      ctx.io.error(Strings.get('sh_err_no_such_file', t));
      code = Exit.FAIL;
      continue;
    }
    if (!FileService.isDir(path)) {
      ctx.io.writeln(t);
      continue;
    }
    if (targets.length > 1) {
      ctx.io.writeln(t + ':');
    }
    const entries = FileService.list(path, p.has('-a'));
    const names = entries.map((e) => e.isDir ? Ansi.boldBlue(e.name + '/') : e.name);
    if (p.has('-l') || p.has('-1')) {
      for (const n of names) {
        ctx.io.writeln(n);
      }
    } else if (names.length > 0) {
      ctx.io.writeln(names.join('  '));
    }
  }
  return code;
}

async function cd(ctx: ShellContext, args: string[]): Promise<number> {
  const target = args.length > 0 ? ctx.resolve(args[0]) : ctx.home();
  if (!FileService.exists(target)) {
    ctx.io.error(Strings.get('sh_err_no_such_file', args[0]));
    return Exit.FAIL;
  }
  if (!FileService.isDir(target)) {
    ctx.io.error(Strings.get('sh_err_not_dir', args[0]));
    return Exit.FAIL;
  }
  ctx.setCwd(target);
  return Exit.OK;
}

async function pwd(ctx: ShellContext, args: string[]): Promise<number> {
  ctx.io.writeln(ctx.display(ctx.cwd()));
  return Exit.OK;
}

async function cat(ctx: ShellContext, args: string[]): Promise<number> {
  if (args.length === 0) {
    ctx.io.error(Strings.get('sh_err_missing_operand', 'cat'));
    return Exit.USAGE;
  }
  let code = Exit.OK;
  for (const a of args) {
    const path = ctx.resolve(a);
    if (FileService.isDir(path)) {
      ctx.io.error(Strings.get('sh_err_is_dir', a));
      code = Exit.FAIL;
      continue;
    }
    try {
      const text = FileService.readText(path);
      ctx.io.write(Ansi.crlf(text));
      if (text.length > 0 && !text.endsWith('\n')) {
        ctx.io.write(Ansi.CRLF);
      }
    } catch (e) {
      ctx.io.error(FileService.exists(path) ? errorMessage(e as Error) : Strings.get('sh_err_no_such_file', a));
      code = Exit.FAIL;
    }
  }
  return code;
}

async function echo(ctx: ShellContext, args: string[]): Promise<number> {
  ctx.io.writeln(args.join(' '));
  return Exit.OK;
}

async function mkdir(ctx: ShellContext, args: string[]): Promise<number> {
  const p = parseArgs(args, []);
  if (p.positional.length === 0) {
    ctx.io.error(Strings.get('sh_err_missing_operand', 'mkdir'));
    return Exit.USAGE;
  }
  for (const a of p.positional) {
    const path = ctx.resolve(a);
    try {
      if (p.has('-p')) {
        FileService.mkdirs(path);
      } else {
        FileService.createDir(path);
      }
    } catch (e) {
      ctx.io.error('mkdir: ' + errorMessage(e as Error));
      return Exit.FAIL;
    }
  }
  ctx.host.filesChanged('');
  return Exit.OK;
}

async function touch(ctx: ShellContext, args: string[]): Promise<number> {
  if (args.length === 0) {
    ctx.io.error(Strings.get('sh_err_missing_operand', 'touch'));
    return Exit.USAGE;
  }
  for (const a of args) {
    const path = ctx.resolve(a);
    if (!FileService.exists(path)) {
      FileService.writeText(path, '');
    }
  }
  ctx.host.filesChanged('');
  return Exit.OK;
}

async function rm(ctx: ShellContext, args: string[]): Promise<number> {
  const p = parseArgs(args, []);
  if (p.positional.length === 0) {
    ctx.io.error(Strings.get('sh_err_missing_operand', 'rm'));
    return Exit.USAGE;
  }
  const recursive = p.has('-r') || p.has('-R');
  let code = Exit.OK;
  for (const a of p.positional) {
    const path = ctx.resolve(a);
    if (path === ctx.home() || !PathUtil.isInside(ctx.home(), path)) {
      ctx.io.error(Strings.get('sh_err_refuse_outside', a));
      code = Exit.FAIL;
    } else if (!FileService.exists(path)) {
      if (!p.has('-f')) {
        ctx.io.error(Strings.get('sh_err_no_such_file', a));
        code = Exit.FAIL;
      }
    } else if (FileService.isDir(path) && !recursive) {
      ctx.io.error(Strings.get('sh_err_rm_dir', a));
      code = Exit.FAIL;
    } else {
      FileService.remove(path);
    }
  }
  ctx.host.filesChanged('');
  return code;
}

/** Shared by mv and cp: copy or move sources into a target (folder or new name). */
async function transfer(ctx: ShellContext, args: string[], name: string, move: boolean): Promise<number> {
  const p = parseArgs(args, []);
  if (p.positional.length < 2) {
    ctx.io.error(Strings.get('sh_err_missing_operand', name));
    return Exit.USAGE;
  }
  const dest = ctx.resolve(p.positional[p.positional.length - 1]);
  const sources = p.positional.slice(0, p.positional.length - 1);
  for (const s of sources) {
    const from = ctx.resolve(s);
    if (!FileService.exists(from)) {
      ctx.io.error(Strings.get('sh_err_no_such_file', s));
      return Exit.FAIL;
    }
    const to = FileService.isDir(dest) ? PathUtil.join(dest, PathUtil.baseName(from)) : dest;
    try {
      if (move) {
        FileService.rename(from, to);
      } else {
        FileService.copy(from, to);
      }
    } catch (e) {
      ctx.io.error(name + ': ' + errorMessage(e as Error));
      return Exit.FAIL;
    }
  }
  ctx.host.filesChanged('');
  return Exit.OK;
}

async function mv(ctx: ShellContext, args: string[]): Promise<number> {
  return transfer(ctx, args, 'mv', true);
}

async function cp(ctx: ShellContext, args: string[]): Promise<number> {
  return transfer(ctx, args, 'cp', false);
}

async function open(ctx: ShellContext, args: string[]): Promise<number> {
  if (args.length === 0) {
    ctx.io.error(Strings.get('sh_err_missing_operand', 'open'));
    return Exit.USAGE;
  }
  for (const a of args) {
    const path = ctx.resolve(a);
    if (!FileService.exists(path)) {
      FileService.writeText(path, '');
      ctx.host.filesChanged(path);
    }
    if (FileService.isDir(path)) {
      ctx.io.error(Strings.get('sh_err_is_dir', a));
      return Exit.FAIL;
    }
    ctx.host.openFile(path);
  }
  return Exit.OK;
}

async function clear(ctx: ShellContext, args: string[]): Promise<number> {
  ctx.clear();
  return Exit.OK;
}

async function help(ctx: ShellContext, args: string[]): Promise<number> {
  ctx.io.writeln(Ansi.bold(Strings.get('sh_help_header')));
  const cmds = ctx.commands();
  let width = 0;
  for (const c of cmds) {
    width = Math.max(width, c.name.length);
  }
  for (const c of cmds) {
    ctx.io.writeln('  ' + Ansi.cyan(c.name.padEnd(width + 2)) + Strings.get(c.summaryKey));
  }
  ctx.io.writeln(Ansi.dim(Strings.get('sh_help_footer')));
  return Exit.OK;
}

async function run(ctx: ShellContext, args: string[]): Promise<number> {
  const cmd = ctx.host.runCommand();
  if (cmd.length === 0) {
    ctx.io.writeln(Strings.get('sh_run_none'));
    return Exit.FAIL;
  }
  ctx.io.writeln(Ansi.dim(Strings.get('sh_run_command', cmd)));
  ctx.io.writeln(Ansi.yellow(Strings.get('sh_run_needs_vm', ctx.host.environmentName())));
  return Exit.FAIL;
}

export function fsCommands(): ShellCommand[] {
  return [
    new FnCommand('ls', 'sh_help_ls', ls),
    new FnCommand('cd', 'sh_help_cd', cd),
    new FnCommand('pwd', 'sh_help_pwd', pwd),
    new FnCommand('cat', 'sh_help_cat', cat),
    new FnCommand('echo', 'sh_help_echo', echo),
    new FnCommand('mkdir', 'sh_help_mkdir', mkdir),
    new FnCommand('touch', 'sh_help_touch', touch),
    new FnCommand('rm', 'sh_help_rm', rm),
    new FnCommand('mv', 'sh_help_mv', mv),
    new FnCommand('cp', 'sh_help_cp', cp),
    new FnCommand('open', 'sh_help_open', open),
    new FnCommand('clear', 'sh_help_clear', clear),
    new FnCommand('help', 'sh_help_help', help),
    new FnCommand('run', 'sh_help_run', run),
  ];
}
