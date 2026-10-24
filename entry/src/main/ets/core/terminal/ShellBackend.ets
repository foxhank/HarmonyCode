/** Receives terminal output (text with ANSI escapes). */
export type OutputSink = (data: string) => void;

/** What a terminal session talks to: the hiSH Linux VM, or the built-in shell. */
export interface ShellBackend {
  /** Short label for the terminal header, e.g. "Alpine Linux" or "Built-in shell". */
  label(): string;
  start(cols: number, rows: number): void;
  /** Raw keystrokes / pasted text from the terminal view. */
  input(data: string): void;
  resize(cols: number, rows: number): void;
  /** Runs one command line as if typed (used by Run). */
  runLine(line: string): void;
  stop(): void;
}

/** What a shell may ask of the IDE. Implemented by the workbench, so the shell stays UI-agnostic. */
export interface ShellHost {
  rootDir(): string;
  projectName(): string;
  environmentName(): string;
  /** Command configured for Run ('' if none). */
  runCommand(): string;
  openFile(path: string): void;
  /** Files changed on disk; payload is the path or '' if unknown. */
  filesChanged(path: string): void;
  gitChanged(): void;
}
