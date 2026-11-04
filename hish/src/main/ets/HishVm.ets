import hish from 'libhish.so';
import { buildQemuArgs, HishVmOptions } from './QemuArgs';

/**
 * The bundled QEMU is the JIT build (as in hiSH's tablet/2in1 package). It needs
 * ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY; without JIT the native layer
 * would prefer a TCI build if one were bundled.
 */
const USE_JIT: boolean = true;

/** Console output as raw bytes (UTF-8 text with terminal escapes). */
export type ConsoleOutput = (bytes: Uint8Array) => void;

/** The hiSH VM of this process. QEMU can be started once per process. */
export class HishVm {
  /** True when QEMU is bundled and loads on this device. */
  static isAvailable(): boolean {
    return hish.isAvailable(USE_JIT);
  }

  /** Boots the VM. Returns '' when started, otherwise the reason it could not start. */
  static start(options: HishVmOptions, onOutput: ConsoleOutput, onExit: (code: number) => void): string {
    return hish.startVm(buildQemuArgs(options), options.serialSocket, USE_JIT,
      (data: ArrayBuffer) => onOutput(new Uint8Array(data)), onExit);
  }

  /** Sends keystrokes / text to the console. False when the console isn't connected yet. */
  static write(text: string): boolean {
    return hish.write(text) >= 0;
  }

  static isPortFree(port: number): boolean {
    return hish.isPortFree(port);
  }
}
