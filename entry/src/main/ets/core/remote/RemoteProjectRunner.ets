import { CommandResult, CommandRunner, OutputListener } from '../agent/CommandRunner';
import { CancelToken } from '../llm/CancelToken';
import { PathUtil } from '../fs/PathUtil';
import { ProjectSync, SyncReport } from './ProjectSync';
import { RemoteCommandRunner } from './RemoteCommandRunner';
import { RemoteConnection } from './RemoteConnection';

/** Told about every sync, so the IDE can refresh files and show status. */
export interface SyncListener {
  syncStarted(): void;
  /** `error` is '' on success. */
  syncFinished(report: SyncReport | null, error: string): void;
}

/**
 * Runs a phone project's commands on a remote computer. The project folder is mirrored to a
 * folder there: before each command local changes go up, after it the command's changes come
 * back, so the agent and the editor keep working on the phone's copy.
 */
export class RemoteProjectRunner implements CommandRunner {
  private conn: RemoteConnection;
  private sync: ProjectSync;
  private inner: RemoteCommandRunner;
  private listener: SyncListener;

  constructor(conn: RemoteConnection, sync: ProjectSync, listener: SyncListener) {
    this.conn = conn;
    this.sync = sync;
    this.inner = new RemoteCommandRunner(conn);
    this.listener = listener;
  }

  describe(): string {
    return this.inner.describe() + ` The project is mirrored to ${this.sync.remoteDir} on that computer and commands ` +
      'run there: files are synced up before each command and the command\'s changes come back afterwards ' +
      '(dependency and build folders such as node_modules stay on the computer). Edit files with the file ' +
      'tools as usual. Output of background jobs is not synced back until the next command.';
  }

  async run(command: string, cwd: string, timeoutMs: number, cancel: CancelToken,
    onOutput: OutputListener): Promise<CommandResult> {
    const remoteCwd = this.sync.toRemote(cwd);
    if (remoteCwd.length === 0) {
      return { exitCode: 1, output: 'The working folder is outside the project.', timedOut: false };
    }
    const before = await this.syncNow(cancel);
    if (before !== null && before.length > 0) {
      onOutput(before + '\n');
    }
    const r = await this.inner.run(command, remoteCwd, timeoutMs, cancel, onOutput);
    // A stopped command still may have changed files.
    const after = await this.syncNow(new CancelToken());
    const notes = [before, after].filter((s: string | null) => s !== null && s.length > 0).join('\n');
    return { exitCode: r.exitCode, output: notes.length > 0 ? r.output + '\n' + notes : r.output, timedOut: r.timedOut };
  }

  /** Syncs and describes anything noteworthy ('' when nothing to say, null on failure, which is reported). */
  async syncNow(cancel: CancelToken): Promise<string | null> {
    this.listener.syncStarted();
    try {
      const sftp = await this.conn.sftp();
      const report = await this.sync.sync(sftp, cancel);
      this.listener.syncFinished(report, '');
      if (report.conflicts.length > 0) {
        return '[sync] Changed on both sides; the phone\'s version was kept and the computer\'s saved as .conflict: ' +
          report.conflicts.join(', ');
      }
      return '';
    } catch (e) {
      const msg = (e as Error).message;
      this.listener.syncFinished(null, msg);
      return '[sync failed: ' + msg + ']';
    }
  }

  /** Remote folder for a project folder (for the terminal). */
  remoteDirFor(localDir: string): string {
    const r = this.sync.toRemote(localDir);
    return r.length > 0 ? r : this.sync.remoteDir;
  }

  static defaultRemoteDir(home: string, projectName: string): string {
    const safe = projectName.replace(new RegExp('[^A-Za-z0-9._-]+', 'g'), '-');
    return PathUtil.join(PathUtil.join(home.length > 0 ? home : '/tmp', 'HarmonyCode'), safe.length > 0 ? safe : 'project');
  }
}
