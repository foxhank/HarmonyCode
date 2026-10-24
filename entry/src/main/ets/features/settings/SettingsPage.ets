import { PageHeader } from '../../components/PageHeader';
import { UiConst } from '../../components/UiConst';
import { appNav } from '../app/AppNavigation';
import { SettingsPanel } from './SettingsPanel';

/** Settings as a full page (opened from the welcome screen). */
@ComponentV2
export struct SettingsPage {
  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.settings_title'), onBack: () => appNav.pop() })
        SettingsPanel()
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      }
      .width(UiConst.FULL)
      .height(UiConst.FULL)
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.app_bg'))
  }
}
