import { CommandResult, CommandRunner, OutputListener } from '../agent/CommandRunner';
import { cancelledError, CancelToken } from '../llm/CancelToken';
import { Utf8Decoder } from './ssh/Bytes';
import { SshChannel } from './ssh/SshChannel';
import { SshClient } from './ssh/SshClient';
import { RemoteConnection } from './RemoteConnection';
import { hostAddress, RemoteOs } from './RemoteHost';
import { RemoteShell } from './RemoteShell';

/** The wrapper prints this around the process id on stderr first, so the job can be killed later. */
const PID_MARK: string = '\u001eHCPID:';
const PID_END: string = '\u001e';
const SIGNALS: Record<string, number> = { 'HUP': 1, 'INT': 2, 'QUIT': 3, 'ABRT': 6, 'KILL': 9, 'SEGV': 11, 'PIPE': 13, 'TERM': 15 };
const SIGNAL_BASE: number = 128;

/**
 * Runs the agent's commands on a remote computer, one SSH exec channel each. On Linux/macOS the
 * command runs in the user's login shell (so PATH, nvm, conda etc. are set up); on Windows in
 * PowerShell. Every command learns its process id up front, so a timeout or Stop kills the whole
 * process tree, not just the channel.
 */
export class RemoteCommandRunner implements CommandRunner {
  private conn: RemoteConnection;

  constructor(conn: RemoteConnection) {
    this.conn = conn;
  }

  describe(): string {
    const p = this.conn.platform;
    const who = hostAddress(this.conn.host);
    if (p === null) {
      return `A remote computer (${who}) over SSH; its operating system is not known yet.`;
    }
    if (p.os === RemoteOs.WINDOWS) {
      return `Windows PowerShell on ${p.release} (${who}, host name ${p.hostname}) over SSH. Write PowerShell ` +
        '(e.g. Get-ChildItem, Select-String, $env:PATH; separate commands with ";"). Each command runs in a fresh ' +
        'PowerShell process: Set-Location and variables do not persist between calls. Native programs (git, ' +
        'node, python) work if they are on the PATH.';
    }
    const shell = p.shell.length > 0 ? p.shell : '/bin/sh';
    return `${p.release} (${who}, host name ${p.hostname}) over SSH. Commands run with ${shell} as a login ` +
      'shell, so the user\'s PATH and tools are available. Each command runs in a fresh shell: cd and variables ' +
      'do not persist between calls. There is no terminal: use non-interactive flags (-y, --no-pager), and ' +
      'sudo only works without a password prompt (sudo -n).';
  }

  async run(command: string, cwd: string, timeoutMs: number, cancel: CancelToken,
    onOutput: OutputListener): Promise<CommandResult> {
    cancel.throwIfCancelled();
    const client = await this.conn.connect();
    const windows = this.conn.platform !== null && this.conn.platform.os === RemoteOs.WINDOWS;
    const ch = await client.openSession();
    const job = new RunningJob(ch, onOutput);
    const ok = await ch.exec(windows ? RemoteCommandRunner.windowsLine(command, cwd) : 'exec sh -s');
    if (!ok) {
      ch.close();
      return { exitCode: -1, output: 'The server refused to run the command.', timedOut: false };
    }
    if (!windows) {
      // The script goes in on stdin, so the login shell (bash, zsh, fish, ...) never has to parse it.
      ch.writeText(RemoteCommandRunner.posixScript(command, cwd, this.conn.platform !== null ? this.conn.platform.shell : ''));
      ch.eof();
    } else {
      ch.eof();
    }
    return job.wait(timeoutMs, cancel, () => this.kill(client, job.pid, windows));
  }

  /** sh reads this from stdin: report the pid, enter the folder, then replace itself with a login shell. */
  static posixScript(command: string, cwd: string, loginShell: string): string {
    const shell = RemoteCommandRunner.posixShell(loginShell);
    return `printf '\\036HCPID:%s\\036' "$$" >&2; cd -- ${RemoteShell.sh(cwd)} || exit 125; ` +
      `exec ${shell} -lc ${RemoteShell.sh(command)} < /dev/null\n`;
  }

  /** The user's shell when it understands POSIX syntax, else sh. */
  private static posixShell(loginShell: string): string {
    const name = loginShell.substring(loginShell.lastIndexOf('/') + 1).replace(new RegExp('\\.exe$'), '');
    return ['bash', 'zsh', 'ksh', 'dash', 'sh', 'ash'].indexOf(name) >= 0 ? RemoteShell.sh(loginShell) : 'sh';
  }

  static windowsLine(command: string, cwd: string): string {
    const script = '$ProgressPreference = \'SilentlyContinue\'; ' +
      '[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); $OutputEncoding = [Console]::OutputEncoding; ' +
      '[Console]::Error.Write([char]30 + \'HCPID:\' + $PID + [char]30); ' +
      `Set-Location -LiteralPath ${RemoteShell.ps(RemoteShell.toWindows(cwd))}; $global:LASTEXITCODE = 0; ` +
      command + '\n' +
      'if (-not $?) { if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } else { exit 1 } }; exit $LASTEXITCODE';
    return RemoteShell.powershell(script);
  }

  private kill(client: SshClient, pid: number, windows: boolean): void {
    if (pid <= 0 || client.isClosed) {
      return;
    }
    const line = windows ? `taskkill /PID ${pid} /T /F` :
      `kill -KILL -- -${pid} 2>/dev/null || kill -KILL ${pid} 2>/dev/null`;
    client.exec(line).catch(() => {
    });
  }
}

/** Collects one command's output and status. */
class RunningJob {
  pid: number = -1;
  private ch: SshChannel;
  private onOutput: OutputListener;
  private output: string = '';
  private out: Utf8Decoder = new Utf8Decoder();
  private err: Utf8Decoder = new Utf8Decoder();
  /** stderr before the pid marker has been seen. */
  private head: string = '';
  private sawPid: boolean = false;

  constructor(ch: SshChannel, onOutput: OutputListener) {
    this.ch = ch;
    this.onOutput = onOutput;
    ch.setOnData((d: Uint8Array) => this.emit(this.out.write(d)));
    ch.setOnStderr((d: Uint8Array) => this.stderr(this.err.write(d)));
  }

  wait(timeoutMs: number, cancel: CancelToken, kill: () => void): Promise<CommandResult> {
    return new Promise<CommandResult>((resolve: (r: CommandResult) => void, reject: (e: Error) => void) => {
      let settled = false;
      let timedOut = false;
      let timer = -1;
      let off: () => void = () => {
      };
      const stop = (): void => {
        kill();
        // Closing the channel too frees it even if the server ignores the kill.
        setTimeout(() => this.ch.close(), 500);
      };
      timer = setTimeout(() => {
        timedOut = true;
        stop();
      }, timeoutMs);
      off = cancel.onCancel(() => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          stop();
          reject(cancelledError());
        }
      });
      this.ch.onClose(() => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        off();
        this.flushHead();
        this.emit(this.out.end() + this.err.end());
        let code = this.ch.exitStatus;
        if (code < 0 && this.ch.exitSignal.length > 0) {
          const n = SIGNALS[this.ch.exitSignal];
          code = SIGNAL_BASE + (n !== undefined ? n : 0);
          this.emit(`\n[killed by signal ${this.ch.exitSignal}]`);
        }
        resolve({ exitCode: timedOut ? -1 : code, output: this.output, timedOut: timedOut });
      });
    });
  }

  private emit(text: string): void {
    if (text.length > 0) {
      this.output += text;
      this.onOutput(text);
    }
  }

  private stderr(text: string): void {
    if (this.sawPid) {
      this.emit(text);
      return;
    }
    this.head += text;
    const start = this.head.indexOf(PID_MARK);
    if (start < 0) {
      // Login scripts may print first; give up waiting for the marker after a while.
      if (this.head.length > 4096) {
        this.flushHead();
      }
      return;
    }
    const end = this.head.indexOf(PID_END, start + PID_MARK.length);
    if (end < 0) {
      return;
    }
    this.pid = Number(this.head.substring(start + PID_MARK.length, end));
    const rest = this.head.substring(0, start) + this.head.substring(end + PID_END.length);
    this.head = '';
    this.sawPid = true;
    this.emit(rest);
  }

  private flushHead(): void {
    if (!this.sawPid) {
      this.sawPid = true;
      this.emit(this.head);
      this.head = '';
    }
  }
}
