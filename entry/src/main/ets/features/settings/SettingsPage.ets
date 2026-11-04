import { PageHeader } from '../../components/PageHeader';
import { UiConst } from '../../components/UiConst';
import { appNav } from '../app/AppNavigation';
import { SettingsPanel } from './SettingsPanel';

/** Settings as a full page (welcome screen, remote workspaces). The route parameter may name a category. */
@ComponentV2
export struct SettingsPage {
  @Local category: string = '';
  @Local ready: boolean = false;

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.settings_title'), onBack: () => appNav.pop() })
        if (this.ready) {
          SettingsPanel({ initialCategory: this.category })
            .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        }
      }
      .width(UiConst.FULL)
      .height(UiConst.FULL)
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.app_bg'))
    .onReady((ctx: NavDestinationContext) => {
      const p = ctx.pathInfo.param as string;
      this.category = typeof p === 'string' ? p : '';
      this.ready = true;
    })
  }
}
