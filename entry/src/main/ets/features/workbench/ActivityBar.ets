import { IconButton } from '../../components/IconButton';
import { UiConst } from '../../components/UiConst';
import { CommandId } from '../commands/CommandService';
import { OverlayId, ViewId } from './WorkbenchState';
import { Workspace } from './Workspace';

interface ActivityItem {
  view: string;
  icon: Resource;
  label: Resource;
}

/** Vertical icon bar on the left (desktop and tablet). */
@ComponentV2
export struct ActivityBar {
  @Param @Require ws: Workspace;

  private items(): ActivityItem[] {
    return [
      { view: ViewId.EXPLORER, icon: $r('app.media.ic_files'), label: $r('app.string.cmd_show_explorer') },
      { view: ViewId.SEARCH, icon: $r('app.media.ic_search'), label: $r('app.string.cmd_show_search') },
      { view: ViewId.SCM, icon: $r('app.media.ic_git_branch'), label: $r('app.string.cmd_show_scm') },
    ];
  }

  private isActive(view: string): boolean {
    return this.ws.ui.sidebarVisible && this.ws.ui.sideView === view;
  }

  @Builder
  badge(count: number) {
    if (count > 0) {
      Text(count.toString())
        .fontSize($r('app.float.font_xxs'))
        .fontColor($r('app.color.badge_text'))
        .backgroundColor($r('app.color.badge_bg'))
        .borderRadius($r('app.float.badge_radius'))
        .constraintSize({ minWidth: $r('app.float.badge_min_size') })
        .height($r('app.float.badge_min_size'))
        .textAlign(TextAlign.Center)
        .padding({ left: $r('app.float.space_xxs'), right: $r('app.float.space_xxs') })
        .position({ right: $r('app.float.space_xs'), bottom: $r('app.float.space_xs') })
        .hitTestBehavior(HitTestMode.Transparent)
    }
  }

  build() {
    Column() {
      ForEach(this.items(), (item: ActivityItem) => {
        Stack() {
          IconButton({
            icon: item.icon, label: item.label, active: this.isActive(item.view),
            buttonSize: $r('app.float.activitybar_width'), iconSize: $r('app.float.icon_size_large'),
            onTap: () => this.ws.ui.showSideView(item.view)
          })
          if (item.view === ViewId.SCM) {
            this.badge(this.ws.scm.changeCount)
          }
        }
        .border({
          width: { left: $r('app.float.activity_indicator_width') },
          color: { left: this.isActive(item.view) ? $r('app.color.accent') : Color.Transparent }
        })
      }, (item: ActivityItem) => item.view)
      Blank()
      IconButton({
        icon: $r('app.media.ic_terminal'), label: $r('app.string.cmd_toggle_terminal'),
        active: this.ws.ui.panelVisible,
        buttonSize: $r('app.float.activitybar_width'), iconSize: $r('app.float.icon_size_large'),
        onTap: () => this.ws.commands.run(CommandId.TOGGLE_TERMINAL)
      })
      IconButton({
        icon: $r('app.media.ic_settings'), label: $r('app.string.cmd_settings'),
        buttonSize: $r('app.float.activitybar_width'), iconSize: $r('app.float.icon_size_large'),
        onTap: () => this.ws.ui.openOverlay(OverlayId.SETTINGS)
      })
    }
    .width($r('app.float.activitybar_width'))
    .height(UiConst.FULL)
    .backgroundColor($r('app.color.activitybar_bg'))
    .border({ width: { right: $r('app.float.border_width') }, color: $r('app.color.border') })
  }
}
