/**
 * Remembers what the agent last read or wrote for each file, so edits are refused when the
 * agent never looked at the file or the file changed on disk since (e.g. the user edited it).
 */
export class ReadTracker {
  private seen: Map<string, string> = new Map();

  record(path: string, content: string): void {
    this.seen.set(path, ReadTracker.fingerprint(content));
  }

  forget(path: string): void {
    this.seen.delete(path);
  }

  hasRead(path: string): boolean {
    return this.seen.has(path);
  }

  /** True when the agent read the file and its content is still what it saw. */
  isCurrent(path: string, content: string): boolean {
    return this.seen.get(path) === ReadTracker.fingerprint(content);
  }

  clear(): void {
    this.seen.clear();
  }

  /** FNV-1a over the text plus its length; enough to notice changes, not a security hash. */
  static fingerprint(text: string): string {
    let h = 0x811c9dc5;
    for (let i = 0; i < text.length; i++) {
      h ^= text.charCodeAt(i);
      h = Math.imul(h, 0x01000193) >>> 0;
    }
    return text.length.toString(36) + ':' + h.toString(36);
  }
}
