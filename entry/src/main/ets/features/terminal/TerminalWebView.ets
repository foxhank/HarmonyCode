import { webview } from '@kit.ArkWeb';
import { AppConfig } from '../../core/common/AppConfig';
import { SettingsStore, settingsStore } from '../../core/settings/SettingsStore';
import { UiConst } from '../../components/UiConst';
import { AppearanceState, appearance } from '../app/Appearance';
import { TERMINAL_JS_NAME, TerminalJsApi } from './TerminalBridge';
import { TerminalModel } from './TerminalModel';

const RAWFILE_SCHEME: string = 'resource://rawfile/';
const BOOT_JS: string = 'window.hcTerm && hcTerm.boot()';

/** Hosts the xterm.js page for a terminal session. */
@ComponentV2
export struct TerminalWebView {
  @Param @Require model: TerminalModel;
  @Local s: SettingsStore = settingsStore;
  @Local look: AppearanceState = appearance;
  private ctl: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.model.bridge.attach(this.ctl);
  }

  aboutToDisappear(): void {
    this.model.bridge.detach(this.ctl);
    this.model.session.detach();
  }

  @Monitor('s.terminalFontSize')
  onSettingsChanged(): void {
    this.model.applySettings();
  }

  @Monitor('look.isDark')
  onThemeChanged(): void {
    this.model.applyTheme();
  }

  build() {
    Web({ src: RAWFILE_SCHEME + AppConfig.TERMINAL_PAGE, controller: this.ctl })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(false)
      .zoomAccess(false)
      .overScrollMode(OverScrollMode.NEVER)
      .backgroundColor($r('app.color.terminal_bg'))
      .javaScriptProxy({
        object: this.model.jsApi,
        name: TERMINAL_JS_NAME,
        methodList: TerminalJsApi.methods(),
        controller: this.ctl
      })
      .onPageEnd(() => {
        this.ctl.runJavaScript(BOOT_JS).catch(() => {
        });
      })
      .width(UiConst.FULL)
      .height(UiConst.FULL)
  }
}
