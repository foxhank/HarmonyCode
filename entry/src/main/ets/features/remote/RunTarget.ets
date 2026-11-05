import { CommandRunner } from '../../core/agent/CommandRunner';
import { OutputSink, ShellBackend } from '../../core/terminal/ShellBackend';

/** Connection states shown for a run target (the same values as ConnState). */
export class TargetState {
  static readonly IDLE: string = 'idle';
  static readonly CONNECTING: string = 'connecting';
  static readonly CONNECTED: string = 'connected';
  static readonly FAILED: string = 'failed';
}

/**
 * Somewhere other than this device that a phone project runs on: one of the user's computers over
 * SSH (RemoteTarget), or the paired desktop app over HarmonyCode Link (DesktopTarget). The project
 * stays on the phone and is mirrored there; commands (agent, Run) execute there.
 */
export interface RunTarget extends CommandRunner {
  state: string;
  error: string;
  syncing: boolean;
  /** When the last sync finished (ms), 0 = never. */
  lastSync: number;
  lastSummary: string;
  conflicts: string[];
  /** Where the project is mirrored, as shown to the user. */
  remoteDir: string;
  /** Name for menus and the status bar. */
  displayName(): string;
  label(): string;
  syncNow(): Promise<void>;
  /** A local file changed: sync soon. */
  schedulePush(): void;
  /** A terminal on the target, in the project's mirror folder. */
  createShell(sink: OutputSink, projectRoot: string): ShellBackend;
  dispose(): void;
}
