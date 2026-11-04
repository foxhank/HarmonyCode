import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { resourceManager } from '@kit.LocalizationKit';

/** Bundled files (resources/rawfile/hish/, filled by scripts/fetch-hish.ps1). */
export class HishAssets {
  static readonly KERNEL: string = 'hish/kernel_aarch64';
  static readonly FIRMWARE: string = 'hish/efi-virtio.rom';
  static readonly ALPINE_ROOTFS: string = 'hish/alpine.qcow2';
  /** Kernel file name inside the firmware folder. */
  static readonly KERNEL_FILE: string = 'kernel_aarch64';
  static readonly FIRMWARE_FILE: string = 'efi-virtio.rom';
}

/** Receives copy progress in bytes. */
export type CopyProgress = (done: number, total: number) => void;

const CHUNK: number = 4 * 1024 * 1024;
const PART_SUFFIX: string = '.part';

/** Size of a bundled raw file in bytes, or -1 if it isn't in this build. */
export function rawFileSize(ctx: common.Context, path: string): number {
  try {
    const fd: resourceManager.RawFileDescriptor = ctx.resourceManager.getRawFdSync(path);
    const size = fd.length;
    ctx.resourceManager.closeRawFdSync(path);
    return size;
  } catch (e) {
    return -1;
  }
}

/**
 * Copies a bundled raw file to `dest` in chunks (images are tens of MB), reporting progress.
 * Writes to dest.part first, so an interrupted copy never looks complete.
 */
export async function copyRawFile(ctx: common.Context, path: string, dest: string,
  onProgress?: CopyProgress): Promise<void> {
  const mgr = ctx.resourceManager;
  const raw: resourceManager.RawFileDescriptor = mgr.getRawFdSync(path);
  const tmp = dest + PART_SUFFIX;
  const out = fileIo.openSync(tmp, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  try {
    const buf = new ArrayBuffer(CHUNK);
    let done = 0;
    while (done < raw.length) {
      const want = Math.min(CHUNK, raw.length - done);
      const n = await fileIo.read(raw.fd, buf, { offset: raw.offset + done, length: want });
      if (n <= 0) {
        throw new Error('unexpected end of ' + path);
      }
      await fileIo.write(out.fd, buf, { length: n });
      done += n;
      if (onProgress !== undefined) {
        onProgress(done, raw.length);
      }
    }
  } finally {
    fileIo.closeSync(out);
    mgr.closeRawFdSync(path);
  }
  fileIo.renameSync(tmp, dest);
}
