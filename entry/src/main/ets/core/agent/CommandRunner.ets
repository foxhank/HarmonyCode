import { CancelToken } from '../llm/CancelToken';

export interface CommandResult {
  /** Process exit status; -1 when it never finished (timeout / cancel). */
  exitCode: number;
  /** stdout and stderr interleaved, as text. */
  output: string;
  timedOut: boolean;
}

/** Receives command output as it is produced, for live display. */
export type OutputListener = (chunk: string) => void;

/**
 * Runs shell command lines for the agent. The app picks the project's Linux VM when it is
 * running, else the built-in shell; tests use a real local shell.
 */
export interface CommandRunner {
  /** What the agent is told about this shell (OS, available commands, limits). */
  describe(): string;
  run(command: string, cwd: string, timeoutMs: number, cancel: CancelToken, onOutput: OutputListener): Promise<CommandResult>;
}
