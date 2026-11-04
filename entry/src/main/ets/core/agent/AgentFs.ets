/** A directory entry. */
export interface FsEntry {
  name: string;
  path: string;
  isDir: boolean;
  /** Bytes; 0 for folders. */
  size: number;
}

/** What `stat` reports about an existing path. */
export interface FsStat {
  isDir: boolean;
  size: number;
}

/**
 * File access the agent's tools need. The app implements it over the sandbox file system and
 * over SFTP for remote hosts; tests implement it over Node's fs. Paths are absolute POSIX-style
 * paths; methods reject with an Error on failure. Asynchronous because remote access is.
 */
export interface AgentFs {
  /** null when the path does not exist. */
  stat(path: string): Promise<FsStat | null>;
  /** Entries of a folder (including hidden ones, excluding `.git`), folders first. */
  list(dir: string): Promise<FsEntry[]>;
  /** UTF-8 text. Rejects for binary or very large files. */
  readText(path: string): Promise<string>;
  /** Writes UTF-8 text, creating parent folders. */
  writeText(path: string, text: string): Promise<void>;
  /** Deletes a file, or a folder with its contents. */
  remove(path: string): Promise<void>;
  mkdirs(path: string): Promise<void>;
  /** Moves or renames; replaces an existing file at `to`. */
  rename(from: string, to: string): Promise<void>;
}

/** Sorts entries folders first, then by name (case-insensitive), as every AgentFs returns them. */
export function sortEntries(entries: FsEntry[]): FsEntry[] {
  return entries.sort((a: FsEntry, b: FsEntry) => {
    if (a.isDir !== b.isDir) {
      return a.isDir ? -1 : 1;
    }
    return a.name.toLowerCase().localeCompare(b.name.toLowerCase());
  });
}
