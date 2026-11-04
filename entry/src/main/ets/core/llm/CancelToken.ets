export type CancelListener = () => void;

const CANCELLED_NAME: string = 'CancelledError';

/** Thrown when an operation stops because its CancelToken was cancelled. */
export class CancelledError extends Error {
  constructor() {
    super('cancelled');
    this.name = CANCELLED_NAME;
  }
}

/** The same error as a plain Error, for APIs typed `(e: Error) => void` (ArkTS forbids passing subclasses there). */
export function cancelledError(): Error {
  const e = new Error('cancelled');
  e.name = CANCELLED_NAME;
  return e;
}

/** Cooperative cancellation shared by the agent loop, model calls, HTTP and tools. */
export class CancelToken {
  private cancelledFlag: boolean = false;
  private listeners: CancelListener[] = [];

  get cancelled(): boolean {
    return this.cancelledFlag;
  }

  cancel(): void {
    if (this.cancelledFlag) {
      return;
    }
    this.cancelledFlag = true;
    const list = this.listeners.slice();
    this.listeners = [];
    for (const fn of list) {
      fn();
    }
  }

  /** Runs `fn` on cancel (right away if already cancelled). Returns an unsubscribe function. */
  onCancel(fn: CancelListener): CancelListener {
    if (this.cancelledFlag) {
      fn();
      return () => {
      };
    }
    this.listeners.push(fn);
    return () => {
      this.listeners = this.listeners.filter((f: CancelListener) => f !== fn);
    };
  }

  throwIfCancelled(): void {
    if (this.cancelledFlag) {
      throw new CancelledError();
    }
  }

  /** Waits `ms`, ending early with CancelledError on cancel. */
  sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (e: Error) => void) => {
      if (this.cancelledFlag) {
        reject(cancelledError());
        return;
      }
      let off: CancelListener = () => {
      };
      const timer = setTimeout(() => {
        off();
        resolve();
      }, ms);
      off = this.onCancel(() => {
        clearTimeout(timer);
        reject(cancelledError());
      });
    });
  }

  static isCancellation(e: Object | undefined | null): boolean {
    return e instanceof Error && e.name === CANCELLED_NAME;
  }
}
