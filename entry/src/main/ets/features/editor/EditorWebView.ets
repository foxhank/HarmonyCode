import { webview } from '@kit.ArkWeb';
import { AppConfig } from '../../core/common/AppConfig';
import { SettingsStore, settingsStore } from '../../core/settings/SettingsStore';
import { UiConst } from '../../components/UiConst';
import { AppearanceState, appearance } from '../app/Appearance';
import { EDITOR_JS_NAME, EditorJsApi } from './EditorBridge';
import { EditorModel } from './EditorModel';

const RAWFILE_SCHEME: string = 'resource://rawfile/';

/** Hosts the CodeMirror page and keeps it in sync with settings and theme. */
@ComponentV2
export struct EditorWebView {
  @Param @Require model: EditorModel;
  @Local s: SettingsStore = settingsStore;
  @Local look: AppearanceState = appearance;
  private ctl: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.model.bridge.attach(this.ctl);
  }

  aboutToDisappear(): void {
    this.model.bridge.detach(this.ctl);
  }

  @Monitor('s.fontSize', 's.tabSize', 's.wordWrap')
  onSettingsChanged(): void {
    this.model.applySettings();
  }

  @Monitor('look.isDark')
  onThemeChanged(): void {
    this.model.applyTheme();
  }

  build() {
    Web({ src: RAWFILE_SCHEME + AppConfig.EDITOR_PAGE, controller: this.ctl })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(false)
      .zoomAccess(false)
      .overScrollMode(OverScrollMode.NEVER)
      .backgroundColor($r('app.color.editor_bg'))
      .javaScriptProxy({
        object: this.model.jsApi,
        name: EDITOR_JS_NAME,
        methodList: EditorJsApi.methods(),
        controller: this.ctl
      })
      .onPageEnd(() => this.model.onEditorReady())
      .width(UiConst.FULL)
      .height(UiConst.FULL)
  }
}
