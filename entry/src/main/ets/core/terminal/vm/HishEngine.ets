import { util } from '@kit.ArkTS';
import { HishVm, PortForward } from 'hish';
import { OutputSink } from '../ShellBackend';
import { VmBootConfig, VmEngine } from './VmEngine';

/** VmEngine over the hiSH runtime module. */
export class HishEngine implements VmEngine {
  private available: boolean | null = null;

  isAvailable(): boolean {
    if (this.available === null) {
      this.available = HishVm.isAvailable();
    }
    return this.available;
  }

  boot(config: VmBootConfig, output: OutputSink, onExit: (code: number) => void): string {
    // Streaming decode keeps multi-byte characters intact across console reads.
    const decoder = util.TextDecoder.create('utf-8');
    const forwards: PortForward[] = config.forwardPorts
      .filter((p: number) => HishVm.isPortFree(p))
      .map((p: number): PortForward => {
        return { host: p, guest: p };
      });
    return HishVm.start({
      kernelPath: config.kernelPath,
      rootfsPath: config.rootfsPath,
      firmwareDir: config.firmwareDir,
      sharedDir: config.sharedDir,
      serialSocket: config.serialSocket,
      cpus: config.cpus,
      memoryMb: config.memoryMb,
      forwards: forwards
    }, (bytes: Uint8Array) => {
      const text = decoder.decodeToString(bytes, { stream: true });
      if (text.length > 0) {
        output(text);
      }
    }, onExit);
  }

  write(data: string): boolean {
    return HishVm.write(data);
  }
}
