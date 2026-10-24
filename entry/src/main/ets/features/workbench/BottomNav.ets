import { UiConst } from '../../components/UiConst';
import { ViewId } from './WorkbenchState';
import { Workspace } from './Workspace';

interface NavItem {
  view: string;
  icon: Resource;
  label: Resource;
}

/** Phone navigation: one tap switches the whole screen between files, code, search, Git, terminal. */
@ComponentV2
export struct BottomNav {
  @Param @Require ws: Workspace;

  private items(): NavItem[] {
    return [
      { view: ViewId.EXPLORER, icon: $r('app.media.ic_files'), label: $r('app.string.nav_files') },
      { view: ViewId.EDITOR, icon: $r('app.media.ic_code'), label: $r('app.string.nav_editor') },
      { view: ViewId.SEARCH, icon: $r('app.media.ic_search'), label: $r('app.string.nav_search') },
      { view: ViewId.SCM, icon: $r('app.media.ic_git_branch'), label: $r('app.string.nav_git') },
      { view: ViewId.TERMINAL, icon: $r('app.media.ic_terminal'), label: $r('app.string.nav_terminal') },
    ];
  }

  build() {
    Row() {
      ForEach(this.items(), (item: NavItem) => {
        Column({ space: $r('app.float.space_xxs') }) {
          Stack() {
            Image(item.icon)
              .width($r('app.float.icon_size'))
              .height($r('app.float.icon_size'))
              .fillColor(this.ws.ui.phoneView === item.view ? $r('app.color.accent') : $r('app.color.icon'))
            if (item.view === ViewId.SCM && this.ws.scm.changeCount > 0) {
              Circle()
                .width($r('app.float.dirty_dot_size'))
                .height($r('app.float.dirty_dot_size'))
                .fill($r('app.color.badge_bg'))
                .position({ right: 0, top: 0 })
            }
          }
          Text(item.label)
            .fontSize($r('app.float.font_xxs'))
            .fontColor(this.ws.ui.phoneView === item.view ? $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        .height(UiConst.FULL)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.ws.ui.phoneView = item.view;
        })
        .accessibilityText(item.label)
      }, (item: NavItem) => item.view)
    }
    .width(UiConst.FULL)
    .height($r('app.float.bottomnav_height'))
    .backgroundColor($r('app.color.bottomnav_bg'))
    .border({ width: { top: $r('app.float.border_width') }, color: $r('app.color.border') })
  }
}
