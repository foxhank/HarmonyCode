import { OutputSink } from '../ShellBackend';

/** How to boot a VM for a project. */
export interface VmBootConfig {
  /** Environment id from the catalog ('alpine', 'ubuntu', ...). */
  envId: string;
  /** Folder with the kernel and root filesystem for this environment. */
  imageDir: string;
  /** Project folder, shared into the VM (mounted at /root/<project>). */
  sharedDir: string;
  cols: number;
  rows: number;
}

/**
 * Native Linux VM (hiSH / qemu-ohos) behind a small interface.
 * The hiSH integration implements this over NAPI; nothing else in the app depends on QEMU.
 */
export interface VmEngine {
  boot(config: VmBootConfig, output: OutputSink): void;
  write(data: string): void;
  resize(cols: number, rows: number): void;
  shutdown(): void;
}
