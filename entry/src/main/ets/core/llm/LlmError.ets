/** A failed model call. `status` is the HTTP status, or 0 for network / stream failures. */
export class LlmError extends Error {
  readonly status: number;
  readonly retryable: boolean;

  constructor(message: string, status: number, retryable: boolean) {
    super(message);
    this.name = 'LlmError';
    this.status = status;
    this.retryable = retryable;
  }

  /** Rate limits, overload and server errors are worth retrying; client errors are not. */
  static isRetryableStatus(status: number): boolean {
    return status === 408 || status === 409 || status === 425 || status === 429 || status >= 500;
  }
}
