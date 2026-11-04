import { common } from '@kit.AbilityKit';
import { copyRawFile, HishAssets, rawFileSize } from 'hish';
import { AppConfig } from '../common/AppConfig';
import { AppPaths } from '../common/AppPaths';
import { Logger, errorMessage } from '../common/Logger';
import { Strings } from '../common/Strings';
import { FileService } from '../fs/FileService';
import { PathUtil } from '../fs/PathUtil';
import { Catalog, EnvironmentDef, ImageSource } from '../project/Catalog';
import { DOWNLOAD_CANCELLED, DownloadHandle, downloadFile } from './ImageDownload';
import { sha256File } from './Sha256';

const TAG: string = 'EnvImages';
const PART_SUFFIX: string = '.part';

export enum ImageStatus {
  MISSING = 'missing',
  INSTALLING = 'installing',
  VERIFYING = 'verifying',
  INSTALLED = 'installed'
}

/** Install state of one environment's root filesystem. Observable for the UI. */
@ObservedV2
export class ImageState {
  @Trace status: string = ImageStatus.MISSING;
  /** 0..1 while installing or verifying. */
  @Trace progress: number = 0;
  /** Last failure, '' if none. */
  @Trace error: string = '';
  /** Size on disk when installed. */
  @Trace diskBytes: number = 0;
}

export type ImageListener = (envId: string) => void;
export type Unsubscribe = () => void;

/**
 * Root filesystem images for the Linux environments: bundled ones are copied out of the app,
 * others are downloaded and checked against their SHA-256. One image per environment,
 * shared by every project that uses it.
 */
export class EnvImages {
  private ctx: common.Context | null = null;
  private states: Map<string, ImageState> = new Map();
  private running: Map<string, Promise<boolean>> = new Map();
  private downloads: Map<string, DownloadHandle> = new Map();
  private listeners: ImageListener[] = [];

  init(ctx: common.Context): void {
    this.ctx = ctx;
  }

  rootfsPath(envId: string): string {
    return PathUtil.join(PathUtil.join(AppPaths.vm, envId), AppConfig.VM_ROOTFS_FILE);
  }

  kernelPath(): string {
    return PathUtil.join(AppPaths.vmFirmware, HishAssets.KERNEL_FILE);
  }

  state(envId: string): ImageState {
    let s = this.states.get(envId);
    if (s === undefined) {
      s = new ImageState();
      const path = this.rootfsPath(envId);
      if (FileService.exists(path)) {
        s.status = ImageStatus.INSTALLED;
        s.diskBytes = FileService.size(path);
      }
      this.states.set(envId, s);
    }
    return s;
  }

  isInstalled(envId: string): boolean {
    return this.state(envId).status === ImageStatus.INSTALLED;
  }

  /** Bytes install() copies or downloads. */
  installBytes(env: EnvironmentDef): number {
    const img = env.image;
    if (img === undefined) {
      return 0;
    }
    if (img.source === ImageSource.BUNDLED) {
      return this.ctx !== null ? Math.max(0, rawFileSize(this.ctx, img.path)) : 0;
    }
    return img.bytes;
  }

  /** Installs the image (no-op if installed). Resolves true when installed; failures land in state().error. */
  install(env: EnvironmentDef): Promise<boolean> {
    const pending = this.running.get(env.id);
    if (pending !== undefined) {
      return pending;
    }
    if (this.isInstalled(env.id)) {
      return Promise.resolve(true);
    }
    const job = this.runInstall(env).finally(() => {
      this.running.delete(env.id);
      this.downloads.delete(env.id);
    });
    this.running.set(env.id, job);
    return job;
  }

  /** Starts installing a VM environment's image in the background (no-op when installed or not a VM). */
  installInBackground(envId: string): void {
    const env = Catalog.environment(envId);
    if (env !== undefined && env.isVm) {
      this.install(env);
    }
  }

  /** Stops a download in progress. */
  cancel(envId: string): void {
    const d = this.downloads.get(envId);
    if (d !== undefined) {
      d.cancel();
    }
  }

  /** Deletes the image and everything installed in it. The caller makes sure it isn't running. */
  remove(envId: string): void {
    const dir = PathUtil.join(AppPaths.vm, envId);
    if (FileService.exists(dir)) {
      FileService.remove(dir);
    }
    const s = this.state(envId);
    s.status = ImageStatus.MISSING;
    s.diskBytes = 0;
    s.progress = 0;
    s.error = '';
    this.notify(envId);
  }

  onChange(fn: ImageListener): Unsubscribe {
    this.listeners.push(fn);
    return () => {
      this.listeners = this.listeners.filter((f: ImageListener) => f !== fn);
    };
  }

  /** Copies the kernel and firmware out of the app package when missing or changed by an update. */
  async ensureFirmware(): Promise<void> {
    const ctx = this.requireContext();
    const files: string[][] = [
      [HishAssets.KERNEL, HishAssets.KERNEL_FILE],
      [HishAssets.FIRMWARE, HishAssets.FIRMWARE_FILE]
    ];
    for (const f of files) {
      const dest = PathUtil.join(AppPaths.vmFirmware, f[1]);
      const size = rawFileSize(ctx, f[0]);
      if (size < 0) {
        throw new Error(Strings.get('env_error_not_bundled', f[0]));
      }
      if (!FileService.exists(dest) || FileService.size(dest) !== size) {
        await copyRawFile(ctx, f[0], dest);
      }
    }
  }

  // ---------- internals ----------

  private async runInstall(env: EnvironmentDef): Promise<boolean> {
    const s = this.state(env.id);
    const img = env.image;
    const dest = this.rootfsPath(env.id);
    const part = dest + PART_SUFFIX;
    s.status = ImageStatus.INSTALLING;
    s.progress = 0;
    s.error = '';
    this.notify(env.id);
    try {
      if (img === undefined) {
        throw new Error(Strings.get('env_error_no_image'));
      }
      FileService.mkdirs(PathUtil.dirName(dest));
      if (img.source === ImageSource.BUNDLED) {
        await copyRawFile(this.requireContext(), img.path, dest,
          (done: number, total: number) => this.setProgress(s, done, total));
      } else {
        await this.download(env.id, img.url, img.bytes, part, s);
        s.status = ImageStatus.VERIFYING;
        s.progress = 0;
        const hash = await sha256File(part, (done: number) => this.setProgress(s, done, img.bytes));
        if (hash !== img.sha256.toLowerCase()) {
          throw new Error(Strings.get('env_error_checksum'));
        }
        FileService.rename(part, dest);
      }
      s.status = ImageStatus.INSTALLED;
      s.diskBytes = FileService.size(dest);
      s.progress = 1;
      this.notify(env.id);
      return true;
    } catch (e) {
      const cancelled = errorMessage(e as Error) === DOWNLOAD_CANCELLED;
      if (!cancelled) {
        Logger.error(TAG, env.id + ': ' + errorMessage(e as Error));
      }
      if (FileService.exists(part)) {
        FileService.remove(part);
      }
      s.status = ImageStatus.MISSING;
      s.progress = 0;
      s.error = cancelled ? '' : errorMessage(e as Error);
      this.notify(env.id);
      return false;
    }
  }

  private async download(envId: string, url: string, expected: number, part: string, s: ImageState): Promise<void> {
    if (FileService.exists(part)) {
      FileService.remove(part);
    }
    const handle = downloadFile(this.requireContext(), url, part, (done: number, total: number) => {
      this.setProgress(s, done, total > 0 ? total : expected);
    });
    this.downloads.set(envId, handle);
    await handle.done;
  }

  private setProgress(s: ImageState, done: number, total: number): void {
    if (total <= 0) {
      return;
    }
    const p = Math.min(1, done / total);
    if (p - s.progress >= AppConfig.VM_PROGRESS_STEP || p === 1) {
      s.progress = p;
    }
  }

  private notify(envId: string): void {
    for (const fn of this.listeners.slice()) {
      fn(envId);
    }
  }

  private requireContext(): common.Context {
    if (this.ctx === null) {
      throw new Error('EnvImages not initialized');
    }
    return this.ctx;
  }
}

export const envImages: EnvImages = new EnvImages();
