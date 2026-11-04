import { IconButton } from '../../components/IconButton';
import { UiConst } from '../../components/UiConst';
import { layoutState } from '../app/LayoutState';
import { CommandId } from '../commands/CommandService';
import { OverlayId, ViewId } from './WorkbenchState';
import { Workspace } from './Workspace';

/** Top bar: project, branch, agent box (wide screens), quick open, run and layout toggles. */
@ComponentV2
export struct TitleBar {
  @Param @Require ws: Workspace;
  @Event onBack: () => void = () => {
  };

  private run(id: string): void {
    this.ws.commands.run(id);
  }

  private phoneTitle(): string {
    const tab = this.ws.editor.active;
    return this.ws.ui.phoneView === ViewId.EDITOR && tab !== undefined ? tab.title : this.ws.project.name;
  }

  @Builder
  moreMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.cmd_palette') }).onClick(() => this.run(CommandId.PALETTE))
      MenuItem({ content: $r('app.string.cmd_save_all') }).onClick(() => this.run(CommandId.SAVE_ALL))
      MenuItem({ content: $r('app.string.cmd_new_file') }).onClick(() => this.run(CommandId.NEW_FILE))
      MenuItem({ content: $r('app.string.cmd_git_branch') }).onClick(() => this.run(CommandId.GIT_BRANCH))
      MenuItem({ content: $r('app.string.cmd_settings') }).onClick(() => this.run(CommandId.SETTINGS))
      MenuItem({ content: $r('app.string.cmd_close_project') }).onClick(() => this.onBack())
    }
  }

  /** Centre of the title bar: opens the agent panel, like a command box for the coding agent. */
  @Builder
  agentBox() {
    Row({ space: $r('app.float.space_s') }) {
      Image($r('app.media.ic_agent'))
        .width($r('app.float.icon_size_small'))
        .height($r('app.float.icon_size_small'))
        .fillColor($r('app.color.accent'))
      Text(this.ws.agent.busy ? $r('app.string.agent_working') : $r('app.string.agent_titlebar_prompt'))
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.text_secondary'))
        .maxLines(UiConst.MAX_LINES_TITLE)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      if (this.ws.agent.busy) {
        LoadingProgress()
          .width($r('app.float.icon_size_small'))
          .height($r('app.float.icon_size_small'))
          .color($r('app.color.accent'))
      }
    }
    .width($r('app.float.title_search_width'))
    .height($r('app.float.title_search_height'))
    .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s') })
    .backgroundColor(this.ws.ui.agentVisible ? $r('app.color.selected_bg') : $r('app.color.input_bg'))
    .borderRadius($r('app.float.radius_m'))
    .border({
      width: $r('app.float.border_width'),
      color: this.ws.ui.agentVisible ? $r('app.color.border_focus') : $r('app.color.input_border')
    })
    .onClick(() => this.ws.ui.toggleAgent())
    .accessibilityText($r('app.string.cmd_toggle_agent'))
  }

  build() {
    Row({ space: $r('app.float.space_xs') }) {
      IconButton({
        icon: $r('app.media.ic_arrow_back'),
        label: $r('app.string.cmd_close_project'),
        buttonSize: layoutState.isPhone ? $r('app.float.icon_button_size_touch') : $r('app.float.icon_button_size'),
        onTap: () => this.onBack()
      })
      if (layoutState.isPhone) {
        Text(this.phoneTitle())
          .fontSize($r('app.float.font_l'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(UiConst.MAX_LINES_TITLE)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        IconButton({ icon: $r('app.media.ic_search'), label: $r('app.string.cmd_quick_open'),
          buttonSize: $r('app.float.icon_button_size_touch'), onTap: () => this.run(CommandId.QUICK_OPEN) })
        IconButton({ icon: $r('app.media.ic_play'), label: $r('app.string.cmd_run'),
          buttonSize: $r('app.float.icon_button_size_touch'), onTap: () => this.run(CommandId.RUN) })
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_more'))
            .width($r('app.float.icon_size'))
            .height($r('app.float.icon_size'))
            .fillColor($r('app.color.icon'))
        }
        .width($r('app.float.icon_button_size_touch'))
        .height($r('app.float.icon_button_size_touch'))
        .backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.action_more'))
        .bindMenu(this.moreMenu())
      } else {
        Text(this.ws.project.name)
          .fontSize($r('app.float.font_m'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(UiConst.MAX_LINES_TITLE)
        if (this.ws.scm.branch.length > 0) {
          Row({ space: $r('app.float.space_xxs') }) {
            Image($r('app.media.ic_git_branch'))
              .width($r('app.float.icon_size_small'))
              .height($r('app.float.icon_size_small'))
              .fillColor($r('app.color.icon'))
            Text(this.ws.scm.branch)
              .fontSize($r('app.float.font_s'))
              .fontColor($r('app.color.text_secondary'))
          }
          .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s') })
          .onClick(() => this.ws.ui.openOverlay(OverlayId.BRANCHES))
        }
        Blank()
        this.agentBox()
        Blank()
        IconButton({ icon: $r('app.media.ic_search'), label: $r('app.string.cmd_quick_open'),
          onTap: () => this.run(CommandId.QUICK_OPEN) })
        IconButton({ icon: $r('app.media.ic_play'), label: $r('app.string.cmd_run'),
          onTap: () => this.run(CommandId.RUN) })
        IconButton({ icon: $r('app.media.ic_sidebar'), label: $r('app.string.cmd_toggle_sidebar'),
          active: this.ws.ui.sidebarVisible, onTap: () => this.run(CommandId.TOGGLE_SIDEBAR) })
        IconButton({ icon: $r('app.media.ic_panel'), label: $r('app.string.cmd_toggle_terminal'),
          active: this.ws.ui.panelVisible, onTap: () => this.run(CommandId.TOGGLE_TERMINAL) })
        IconButton({ icon: $r('app.media.ic_agent'), label: $r('app.string.cmd_toggle_agent'),
          active: this.ws.ui.agentVisible, onTap: () => this.ws.ui.toggleAgent() })
        IconButton({ icon: $r('app.media.ic_settings'), label: $r('app.string.cmd_settings'),
          onTap: () => this.run(CommandId.SETTINGS) })
      }
    }
    .width(UiConst.FULL)
    .height(layoutState.isPhone ? $r('app.float.titlebar_height_touch') : $r('app.float.titlebar_height'))
    .padding({ left: $r('app.float.space_xs'), right: $r('app.float.space_xs') })
    .backgroundColor($r('app.color.titlebar_bg'))
    .border({ width: { bottom: $r('app.float.border_width') }, color: $r('app.color.border') })
  }
}
