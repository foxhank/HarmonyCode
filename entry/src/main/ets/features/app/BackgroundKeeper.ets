import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { Logger, errorMessage } from '../../core/common/Logger';

const TAG: string = 'BackgroundKeeper';
const CAPABILITY: string = 'SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask';

/**
 * Keeps the app running with the screen off while the agent works (a "data transfer"
 * continuous task, shown to the user as a notification). Without it the system freezes the app
 * soon after the screen locks, which would drop remote connections mid-task. Holders are
 * counted, so several busy agents share one task.
 */
export class BackgroundKeeper {
  private static ctx: common.UIAbilityContext | null = null;
  private static holders: Set<string> = new Set();
  private static running: boolean = false;
  private static agent: WantAgent | null = null;

  static init(ctx: common.UIAbilityContext): void {
    BackgroundKeeper.ctx = ctx;
  }

  static acquire(holder: string): void {
    BackgroundKeeper.holders.add(holder);
    if (!BackgroundKeeper.running) {
      BackgroundKeeper.start();
    }
  }

  static release(holder: string): void {
    BackgroundKeeper.holders.delete(holder);
    if (BackgroundKeeper.holders.size === 0) {
      BackgroundKeeper.stop();
    }
  }

  static releaseAll(): void {
    BackgroundKeeper.holders.clear();
    BackgroundKeeper.stop();
  }

  private static async start(): Promise<void> {
    const ctx = BackgroundKeeper.ctx;
    if (ctx === null || !canIUse(CAPABILITY)) {
      return;
    }
    BackgroundKeeper.running = true;
    try {
      if (BackgroundKeeper.agent === null) {
        const info: wantAgent.WantAgentInfo = {
          wants: [{ bundleName: ctx.abilityInfo.bundleName, abilityName: ctx.abilityInfo.name }],
          actionType: wantAgent.OperationType.START_ABILITY,
          requestCode: 0,
          actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
        };
        BackgroundKeeper.agent = await wantAgent.getWantAgent(info);
      }
      await backgroundTaskManager.startBackgroundRunning(ctx, backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
        BackgroundKeeper.agent as WantAgent);
      // Everything may have finished while this was starting.
      if (BackgroundKeeper.holders.size === 0) {
        BackgroundKeeper.stop();
      }
    } catch (e) {
      BackgroundKeeper.running = false;
      Logger.warn(TAG, 'start: ' + errorMessage(e as Error));
    }
  }

  private static stop(): void {
    const ctx = BackgroundKeeper.ctx;
    if (!BackgroundKeeper.running || ctx === null) {
      return;
    }
    BackgroundKeeper.running = false;
    backgroundTaskManager.stopBackgroundRunning(ctx).catch((e: Error) => {
      Logger.warn(TAG, 'stop: ' + errorMessage(e));
    });
  }
}
