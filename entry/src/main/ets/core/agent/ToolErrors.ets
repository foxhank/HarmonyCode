/** Bad or missing arguments; reported back to the model so it can correct the call. */
export class ToolInputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ToolInputError';
  }
}
