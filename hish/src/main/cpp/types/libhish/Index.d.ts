/** True when QEMU can be loaded on this device. */
export const isAvailable: (useJit: boolean) => boolean;

/**
 * Starts QEMU with `args` (argv, including argv[0]) on a background thread and connects to the
 * guest's serial console at `serialSocket`. Only one VM can be started per process.
 * Returns '' when started, otherwise the reason it could not start.
 */
export const startVm: (args: string[], serialSocket: string, useJit: boolean,
  onOutput: (data: ArrayBuffer) => void, onExit: (code: number) => void) => string;

/** Writes UTF-8 text to the serial console. Returns bytes written, or -1 when not connected. */
export const write: (text: string) => number;

/** True when 127.0.0.1:port is free to bind (used before forwarding ports into the VM). */
export const isPortFree: (port: number) => boolean;
