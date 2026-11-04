import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { AppConfig } from './AppConfig';

/** Well-known folders inside the app sandbox. Initialized once at startup. */
export class AppPaths {
  /** Projects live here: <files>/workspace. Shared into Linux VMs at /mnt/share. */
  static workspace: string = '';
  /** IDE files the VM reads (terminal size), hidden in the workspace: <files>/workspace/.harmonycode */
  static vmControl: string = '';
  /** VM images: <files>/vm/<envId>/rootfs.qcow2 */
  static vm: string = '';
  /** Kernel and firmware shared by every VM: <files>/vm/firmware */
  static vmFirmware: string = '';
  /** Short-lived files such as the VM console socket: <temp> */
  static temp: string = '';

  static init(ctx: common.Context): void {
    AppPaths.workspace = ctx.filesDir + '/' + AppConfig.WORKSPACE_DIR;
    AppPaths.vmControl = AppPaths.workspace + '/' + AppConfig.VM_CONTROL_DIR;
    AppPaths.vm = ctx.filesDir + '/' + AppConfig.VM_DIR;
    AppPaths.vmFirmware = AppPaths.vm + '/' + AppConfig.VM_FIRMWARE_DIR;
    AppPaths.temp = ctx.tempDir;
    for (const d of [AppPaths.workspace, AppPaths.vmControl, AppPaths.vm, AppPaths.vmFirmware]) {
      if (!fileIo.accessSync(d)) {
        fileIo.mkdirSync(d, true);
      }
    }
  }
}
