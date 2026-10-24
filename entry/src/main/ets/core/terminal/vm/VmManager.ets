import { AppPaths } from '../../common/AppPaths';
import { FileService } from '../../fs/FileService';
import { PathUtil } from '../../fs/PathUtil';
import { VmEngine } from './VmEngine';

/** Files every environment image folder must contain. */
const REQUIRED_IMAGE_FILES: string[] = ['kernel', 'rootfs.img'];

export enum VmState {
  /** No VM engine in this build yet (hiSH not integrated). */
  ENGINE_MISSING = 'engineMissing',
  /** Engine present, but this environment's image isn't downloaded. */
  NOT_INSTALLED = 'notInstalled',
  READY = 'ready'
}

/**
 * Knows which VM environments are usable. The engine is registered at startup by the
 * hiSH integration module; until then every VM environment reports ENGINE_MISSING.
 */
export class VmManager {
  private static engineFactory: (() => VmEngine) | null = null;

  static registerEngine(factory: () => VmEngine): void {
    VmManager.engineFactory = factory;
  }

  static imageDir(envId: string): string {
    return PathUtil.join(AppPaths.vm, envId);
  }

  static state(envId: string): VmState {
    if (VmManager.engineFactory === null) {
      return VmState.ENGINE_MISSING;
    }
    const dir = VmManager.imageDir(envId);
    for (const f of REQUIRED_IMAGE_FILES) {
      if (!FileService.exists(PathUtil.join(dir, f))) {
        return VmState.NOT_INSTALLED;
      }
    }
    return VmState.READY;
  }

  /** A new engine instance, or null when none is registered. */
  static createEngine(): VmEngine | null {
    return VmManager.engineFactory !== null ? VmManager.engineFactory() : null;
  }
}
