import { CommandResult, CommandRunner, OutputListener } from '../agent/CommandRunner';
import { CancelToken } from '../llm/CancelToken';
import { SyncReport } from '../remote/ProjectSync';
import { SyncListener } from '../remote/RemoteProjectRunner';
import { LinkClient } from './LinkClient';
import { DesktopInfo } from './LinkSession';
import { LinkSync } from './LinkSync';

/** Hands out the live client, connecting (or reconnecting) when needed. */
export interface LinkProvider {
  client(): Promise<LinkClient>;
  /** What the desktop reported, once connected. */
  info(): DesktopInfo | null;
}

/**
 * Runs a phone project's commands on the paired desktop over HarmonyCode Link: sync up, run in
 * the matching folder there, sync back.
 */
export class LinkRunner implements CommandRunner {
  private provider: LinkProvider;
  private sync: LinkSync;
  private listener: SyncListener;

  constructor(provider: LinkProvider, sync: LinkSync, listener: SyncListener) {
    this.provider = provider;
    this.sync = sync;
    this.listener = listener;
  }

  describe(): string {
    const i = this.provider.info();
    const where = i !== null ? `${i.os} desktop "${i.name}" (host ${i.hostname})` : 'the user\'s paired desktop';
    const shell = i !== null && i.os === 'Windows' ? 'Windows PowerShell' : '/bin/sh';
    return `${where} over HarmonyCode Link (encrypted, LAN). Commands run there with ${shell}, in the project's ` +
      `mirror folder "${this.sync.desktopFolder}" of the desktop's shared workspace. The project syncs both ways ` +
      'in real time and before and after every command, so edit files with the file tools as usual. Commands are ' +
      'non-interactive.';
  }

  async run(command: string, cwd: string, timeoutMs: number, cancel: CancelToken,
    onOutput: OutputListener): Promise<CommandResult> {
    const folder = this.sync.toDesktop(cwd);
    if (folder.length === 0 && this.sync.desktopFolder.length > 0) {
      return { exitCode: 1, output: 'The working folder is outside the project.', timedOut: false };
    }
    const client = await this.provider.client();
    const before = await this.syncNow(client);
    let output = '';
    const r = await client.exec(command, folder, timeoutMs, cancel, (t: string) => {
      output += t;
      onOutput(t);
    });
    const after = await this.syncNow(client);
    const notes = [before, after].filter((s: string) => s.length > 0).join('\n');
    return { exitCode: r.exitCode, output: notes.length > 0 ? output + '\n' + notes : output, timedOut: r.timedOut };
  }

  /** Syncs; returns a note for the agent ('' when there is nothing to say). */
  async syncNow(client: LinkClient): Promise<string> {
    this.listener.syncStarted();
    try {
      const report: SyncReport = await this.sync.sync(client, false);
      this.listener.syncFinished(report, '');
      return report.conflicts.length > 0 ? '[sync] Changed on both sides; the phone\'s version was kept and the ' +
        'desktop\'s saved as .conflict: ' + report.conflicts.join(', ') : '';
    } catch (e) {
      this.listener.syncFinished(null, (e as Error).message);
      return '[sync failed: ' + (e as Error).message + ']';
    }
  }
}
