import { OutputSink } from '../ShellBackend';

/** How to boot the Linux VM. */
export interface VmBootConfig {
  kernelPath: string;
  rootfsPath: string;
  firmwareDir: string;
  /** Host folder shared into the VM (appears at AppConfig.VM_GUEST_SHARE). */
  sharedDir: string;
  /** Unix socket path for the serial console. */
  serialSocket: string;
  cpus: number;
  memoryMb: number;
  /** Guest TCP ports to expose at the same port on 127.0.0.1 (taken ports are skipped). */
  forwardPorts: number[];
}

/**
 * A Linux VM behind a small interface (implemented by HishEngine over hiSH's QEMU).
 * Nothing else in the app depends on QEMU. A VM boots at most once per process.
 */
export interface VmEngine {
  isAvailable(): boolean;
  /** Boots the VM. Returns '' when started, otherwise the reason. Output is decoded UTF-8 text. */
  boot(config: VmBootConfig, output: OutputSink, onExit: (code: number) => void): string;
  /** Sends text to the console. False when the console isn't connected yet. */
  write(data: string): boolean;
}
