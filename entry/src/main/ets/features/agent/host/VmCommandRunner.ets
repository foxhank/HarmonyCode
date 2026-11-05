import { CommandResult, CommandRunner, OutputListener } from '../../../core/agent/CommandRunner';
import { AppPaths } from '../../../core/common/AppPaths';
import { FileService } from '../../../core/fs/FileService';
import { PathUtil } from '../../../core/fs/PathUtil';
import { cancelledError, CancelToken } from '../../../core/llm/CancelToken';
import { GuestCommands } from '../../../core/terminal/vm/GuestCommands';
import { VmPhase, vmRuntime } from '../../../core/terminal/vm/VmRuntime';
import { InstalledTools } from '../../environment/ToolsModel';

const JOB_DIR: string = 'agent-jobs';
const POLL_MS: number = 250;
/** Live output is streamed while the output file is smaller than this; the rest arrives at the end. */
const STREAM_MAX_BYTES: number = 2 * 1024 * 1024;
/** Extra time the VM gets beyond the command timeout to write its exit status. */
const EXIT_GRACE_MS: number = 5000;
/** SIGKILL exit status from `timeout -s KILL`. */
const KILLED_STATUS: number = 137;
const PID_KEEP_MS: number = 30000;

/** What the runner needs from the workbench. */
export interface VmRunnerHost {
  /** Opens the terminal so the VM boots (it starts when a terminal attaches). */
  ensureVmStarted(): void;
  environmentName(): string;
  environmentId(): string;
}

/**
 * Runs agent commands inside the project's Linux VM. The command is typed into the VM shell as a
 * background job; output and exit status come back through files in the shared workspace folder,
 * so the user's terminal stays usable and every command the agent runs is visible there.
 */
export class VmCommandRunner implements CommandRunner {
  private host: VmRunnerHost;
  private seq: number = 0;

  constructor(host: VmRunnerHost) {
    this.host = host;
  }

  describe(): string {
    return `Linux VM (${this.host.environmentName()}) running a POSIX sh with the usual tools; install ` +
      'packages with the distribution\'s package manager (e.g. `apk add` on Alpine). Commands start in the ' +
      'project folder (shared with the VM). Each command runs in a fresh non-interactive shell: `cd` and ' +
      'variables do not persist between calls. Commands appear in the user\'s terminal.' + this.toolsNote();
  }

  private toolsNote(): string {
    const installed = InstalledTools.summary(this.host.environmentId());
    return installed.length > 0 ? ' Installed languages and tools: ' + installed + '.' : '';
  }

  async run(command: string, cwd: string, timeoutMs: number, cancel: CancelToken,
    onOutput: OutputListener): Promise<CommandResult> {
    const guestCwd = GuestCommands.guestPath(cwd);
    if (guestCwd.length === 0) {
      return { exitCode: 1, output: 'The project folder is not shared with the Linux VM.', timedOut: false };
    }
    if (vmRuntime.phase === VmPhase.STOPPED) {
      return { exitCode: 1, output: 'The Linux VM has stopped. Restart the app to start it again.', timedOut: false };
    }
    if (vmRuntime.phase === VmPhase.IDLE) {
      this.host.ensureVmStarted();
    }
    const dir = PathUtil.join(AppPaths.vmControl, JOB_DIR);
    FileService.mkdirs(dir);
    this.seq++;
    const id = Date.now().toString(36) + '-' + this.seq;
    const out = PathUtil.join(dir, id + '.out');
    const exit = PathUtil.join(dir, id + '.exit');
    const pid = PathUtil.join(dir, id + '.pid');
    vmRuntime.run(VmCommandRunner.jobLine(command, guestCwd, Math.ceil(timeoutMs / 1000), out, exit, pid));
    try {
      return await this.wait(out, exit, pid, timeoutMs, cancel, onOutput);
    } finally {
      VmCommandRunner.removeFiles([out, exit, exit + '.tmp']);
      // A kill typed into the VM still needs the pid file; remove it once that has run.
      setTimeout(() => VmCommandRunner.removeFiles([pid]), PID_KEEP_MS);
    }
  }

  /**
   *  { cd DIR && setsid sh -c 'echo $$ > PID; exec timeout -s KILL N sh -c CMD' > OUT 2>&1 < /dev/null;
   *    echo $? > EXIT.tmp; mv EXIT.tmp EXIT; } &
   * setsid gives the job its own process group, so stopping it kills everything it started.
   */
  private static jobLine(cmd: string, cwd: string, timeoutSec: number, out: string, exit: string, pid: string): string {
    const q = (s: string): string => GuestCommands.quote(s);
    const g = (host: string): string => q(GuestCommands.guestPath(host));
    const inner = `echo $$ > ${g(pid)}; exec timeout -s KILL ${timeoutSec} sh -c ${q(cmd)}`;
    return ` { cd ${q(cwd)} && setsid sh -c ${q(inner)} > ${g(out)} 2>&1 < /dev/null; ` +
      `echo $? > ${g(exit + '.tmp')}; mv ${g(exit + '.tmp')} ${g(exit)}; } &`;
  }

  private wait(out: string, exit: string, pid: string, timeoutMs: number, cancel: CancelToken,
    onOutput: OutputListener): Promise<CommandResult> {
    return new Promise<CommandResult>((resolve: (r: CommandResult) => void, reject: (e: Error) => void) => {
      const started = Date.now();
      let sent = 0;
      let settled = false;
      const readOut = (): string => {
        try {
          return FileService.exists(out) ? FileService.readText(out) : '';
        } catch (e) {
          return ''; // binary output or being written
        }
      };
      const stream = (): void => {
        if (FileService.size(out) > STREAM_MAX_BYTES) {
          return;
        }
        const text = readOut();
        if (text.length > sent) {
          onOutput(text.substring(sent));
          sent = text.length;
        }
      };
      const done = (r: CommandResult | null, e: Error | null): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearInterval(timer);
        off();
        if (e !== null) {
          reject(e);
        } else if (r !== null) {
          resolve(r);
        }
      };
      const timer = setInterval(() => {
        stream();
        if (FileService.exists(exit)) {
          let status = -1;
          try {
            status = Number(FileService.readText(exit).trim());
          } catch (e) {
            status = -1;
          }
          const elapsed = Date.now() - started;
          const output = readOut();
          if (output.length > sent) {
            onOutput(output.substring(sent));
          }
          done({
            exitCode: Number.isNaN(status) ? -1 : status, output: output,
            timedOut: status === KILLED_STATUS && elapsed >= timeoutMs - POLL_MS
          }, null);
        } else if (Date.now() - started > timeoutMs + EXIT_GRACE_MS) {
          VmCommandRunner.kill(pid);
          done({ exitCode: -1, output: readOut(), timedOut: true }, null);
        }
      }, POLL_MS);
      const off = cancel.onCancel(() => {
        VmCommandRunner.kill(pid);
        done(null, cancelledError());
      });
    });
  }

  private static removeFiles(paths: string[]): void {
    for (const f of paths) {
      try {
        if (FileService.exists(f)) {
          FileService.remove(f);
        }
      } catch (e) {
        // already gone
      }
    }
  }

  /** Kills the job's process group, if it got as far as writing its pid. */
  private static kill(pid: string): void {
    const p = GuestCommands.quote(GuestCommands.guestPath(pid));
    vmRuntime.run(` [ -f ${p} ] && kill -KILL -- -$(cat ${p}) 2>/dev/null`);
  }
}
