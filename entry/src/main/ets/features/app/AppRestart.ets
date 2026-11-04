import { common, Want } from '@kit.AbilityKit';
import { Logger, errorMessage } from '../../core/common/Logger';

const TAG: string = 'AppRestart';
/** Want parameter naming the project to reopen after a restart. */
const PROJECT_PARAM: string = 'projectId';

/**
 * Restarts the app, optionally reopening a project. Needed to switch Linux environments,
 * because QEMU can boot only once per process.
 */
export class AppRestart {
  private static ctx: common.UIAbilityContext | null = null;
  private static pendingProject: string = '';

  /** Called from EntryAbility.onCreate with the launch Want. */
  static init(ctx: common.UIAbilityContext, want: Want): void {
    AppRestart.ctx = ctx;
    const params = want.parameters;
    const id = params !== undefined ? params[PROJECT_PARAM] : undefined;
    AppRestart.pendingProject = typeof id === 'string' ? id : '';
  }

  /** Project to reopen after a restart ('' if none); returned once. */
  static takePendingProject(): string {
    const id = AppRestart.pendingProject;
    AppRestart.pendingProject = '';
    return id;
  }

  /** Restarts now. Returns '' on success, otherwise the error. */
  static restart(projectId: string): string {
    const ctx = AppRestart.ctx;
    if (ctx === null) {
      return 'not initialized';
    }
    const want: Want = {
      bundleName: ctx.abilityInfo.bundleName,
      abilityName: ctx.abilityInfo.name,
      parameters: { 'projectId': projectId }
    };
    try {
      ctx.getApplicationContext().restartApp(want);
      return '';
    } catch (e) {
      const msg = errorMessage(e as Error);
      Logger.error(TAG, msg);
      return msg;
    }
  }
}
