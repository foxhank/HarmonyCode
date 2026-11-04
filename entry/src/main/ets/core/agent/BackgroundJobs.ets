import { CancelToken } from '../llm/CancelToken';
import { CommandResult, CommandRunner } from './CommandRunner';

/** Output kept per background job (the newest part). */
const KEEP_CHARS: number = 1024 * 1024;

/** A command started with run_in_background. */
export class BackgroundJob {
  readonly id: string;
  readonly command: string;
  readonly startedAt: number;
  output: string = '';
  /** Characters dropped from the front of `output` to stay under the cap. */
  dropped: number = 0;
  /** How far the model has read (absolute character position). */
  readPos: number = 0;
  done: boolean = false;
  exitCode: number = -1;
  timedOut: boolean = false;
  killed: boolean = false;
  readonly cancel: CancelToken = new CancelToken();
  private waiters: (() => void)[] = [];

  constructor(id: string, command: string) {
    this.id = id;
    this.command = command;
    this.startedAt = Date.now();
  }

  append(chunk: string): void {
    this.output += chunk;
    if (this.output.length > KEEP_CHARS) {
      const cut = this.output.length - KEEP_CHARS;
      this.output = this.output.substring(cut);
      this.dropped += cut;
    }
    this.wake();
  }

  finish(r: CommandResult): void {
    this.done = true;
    this.exitCode = r.exitCode;
    this.timedOut = r.timedOut;
    this.wake();
  }

  /** Resolves when new output arrives, the job ends, or `ms` pass. */
  waitForChange(ms: number, cancel: CancelToken): Promise<void> {
    if (this.done || ms <= 0 || cancel.cancelled) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void) => {
      let settled = false;
      let timer = -1;
      let off: () => void = () => {
      };
      const finish = (): void => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          off();
          resolve();
        }
      };
      timer = setTimeout(finish, ms);
      off = cancel.onCancel(finish);
      this.waiters.push(finish);
    });
  }

  /** Output since the last read. */
  takeNew(): string {
    const start = Math.max(this.readPos, this.dropped);
    const skipped = start - this.readPos;
    const text = this.output.substring(start - this.dropped);
    this.readPos = this.dropped + this.output.length;
    return (skipped > 0 ? `[${skipped} older characters were discarded]\n` : '') + text;
  }

  private wake(): void {
    const ws = this.waiters;
    this.waiters = [];
    for (const w of ws) {
      w();
    }
  }
}

/**
 * Long-running commands the agent starts and checks on later (dev servers, watchers, long builds).
 * Works with any CommandRunner: the job is a normal run whose output is collected here.
 */
export class BackgroundJobs {
  private jobs: Map<string, BackgroundJob> = new Map();
  private seq: number = 0;

  start(runner: CommandRunner, command: string, cwd: string, timeoutMs: number): BackgroundJob {
    this.seq++;
    const job = new BackgroundJob('job' + this.seq, command);
    this.jobs.set(job.id, job);
    runner.run(command, cwd, timeoutMs, job.cancel, (chunk: string) => job.append(chunk))
      .then((r: CommandResult) => job.finish(r))
      .catch((e: Error) => {
        job.append('\n' + e.message);
        job.finish({ exitCode: -1, output: '', timedOut: false });
      });
    return job;
  }

  get(id: string): BackgroundJob | undefined {
    return this.jobs.get(id.trim());
  }

  list(): BackgroundJob[] {
    return Array.from(this.jobs.values());
  }

  kill(id: string): boolean {
    const j = this.jobs.get(id.trim());
    if (j === undefined || j.done) {
      return false;
    }
    j.killed = true;
    j.cancel.cancel();
    return true;
  }

  killAll(): void {
    for (const j of this.jobs.values()) {
      if (!j.done) {
        j.killed = true;
        j.cancel.cancel();
      }
    }
  }

  clear(): void {
    this.killAll();
    this.jobs.clear();
  }
}
