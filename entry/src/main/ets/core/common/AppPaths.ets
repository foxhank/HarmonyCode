import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { AppConfig } from './AppConfig';

/** Well-known folders inside the app sandbox. Initialized once at startup. */
export class AppPaths {
  /** Projects live here: <files>/workspace */
  static workspace: string = '';
  /** VM images and state live here: <files>/vm */
  static vm: string = '';

  static init(ctx: common.Context): void {
    AppPaths.workspace = ctx.filesDir + '/' + AppConfig.WORKSPACE_DIR;
    AppPaths.vm = ctx.filesDir + '/' + AppConfig.VM_DIR;
    for (const d of [AppPaths.workspace, AppPaths.vm]) {
      if (!fileIo.accessSync(d)) {
        fileIo.mkdirSync(d, true);
      }
    }
  }
}
