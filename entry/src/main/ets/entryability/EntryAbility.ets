import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { AppPaths } from '../core/common/AppPaths';
import { Logger, errorMessage } from '../core/common/Logger';
import { Strings } from '../core/common/Strings';
import { Catalog } from '../core/project/Catalog';
import { projectRepository } from '../core/project/ProjectRepository';
import { settingsStore } from '../core/settings/SettingsStore';
import { AppServices } from '../features/app/AppServices';
import { appearance } from '../features/app/Appearance';
import { ColorUtil } from '../features/app/ColorUtil';
import { layoutState } from '../features/app/LayoutState';

const TAG: string = 'EntryAbility';
const MAIN_PAGE: string = 'pages/Index';

/** Starts services in dependency order, then keeps window size and color mode up to date. */
export default class EntryAbility extends UIAbility {
  private win: window.Window | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const ctx = this.context;
    try {
      Strings.init(ctx);
      ColorUtil.init(ctx);
      AppPaths.init(ctx);
      settingsStore.load(ctx);
      Catalog.load(ctx);
      projectRepository.load(ctx);
      appearance.init(ctx);
      appearance.applyLanguage(settingsStore.language);
      appearance.applyTheme(settingsStore.theme);
    } catch (e) {
      Logger.error(TAG, 'startup failed: ' + errorMessage(e as Error));
    }
  }

  onConfigurationUpdate(config: Configuration): void {
    appearance.onSystemColorMode(config.colorMode);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.getMainWindow().then((win: window.Window) => {
      this.win = win;
      this.updateLayout(win.getWindowProperties().windowRect);
      win.on('windowSizeChange', (size: window.Size) => this.updateLayout(size));
    }).catch((e: Error) => Logger.error(TAG, 'main window: ' + errorMessage(e)));

    windowStage.loadContent(MAIN_PAGE, (err) => {
      if (err.code) {
        Logger.error(TAG, 'loadContent failed: ' + JSON.stringify(err));
      }
    });
  }

  onWindowStageDestroy(): void {
    if (this.win !== null) {
      this.win.off('windowSizeChange');
      this.win = null;
    }
  }

  onDestroy(): void {
    AppServices.git.dispose();
  }

  /** Window sizes arrive in px; layout breakpoints are in vp. */
  private updateLayout(size: window.Size | window.Rect): void {
    let scale = 1;
    try {
      scale = display.getDefaultDisplaySync().densityPixels;
    } catch (e) {
      Logger.warn(TAG, 'display density: ' + errorMessage(e as Error));
    }
    if (!(scale > 0)) {
      scale = 1;
    }
    layoutState.update(size.width / scale, size.height / scale);
  }
}
