export type Listener = (payload: string) => void;
export type Unsubscribe = () => void;

/** Event names. Payloads are plain strings (a path, or '' when not needed). */
export class Events {
  /** Something changed on disk under the project; payload = changed path or '' for "unknown". */
  static readonly FILES_CHANGED: string = 'files.changed';
  /** A file was written by the editor; payload = path. */
  static readonly FILE_SAVED: string = 'file.saved';
  /** A file or folder was renamed; payload = JSON {from, to}. */
  static readonly FILE_RENAMED: string = 'file.renamed';
  /** A file or folder was deleted; payload = path. */
  static readonly FILE_DELETED: string = 'file.deleted';
  /** The repository changed (commit, checkout, pull...). */
  static readonly GIT_CHANGED: string = 'git.changed';
}

export interface RenamePayload {
  from: string;
  to: string;
}

/**
 * Small publish/subscribe hub so features don't hold references to each other.
 * One bus per open workspace; disposed when the project closes.
 */
export class EventBus {
  private listeners: Map<string, Listener[]> = new Map();

  on(event: string, fn: Listener): Unsubscribe {
    const list = this.listeners.get(event) ?? [];
    list.push(fn);
    this.listeners.set(event, list);
    return () => {
      const cur = this.listeners.get(event) ?? [];
      this.listeners.set(event, cur.filter((f: Listener) => f !== fn));
    };
  }

  emit(event: string, payload: string = ''): void {
    const list = this.listeners.get(event);
    if (list === undefined) {
      return;
    }
    for (const fn of list.slice()) {
      fn(payload);
    }
  }

  clear(): void {
    this.listeners.clear();
  }
}
