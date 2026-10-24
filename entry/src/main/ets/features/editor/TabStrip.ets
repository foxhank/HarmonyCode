import { UiConst } from '../../components/UiConst';
import { layoutState } from '../app/LayoutState';
import { EditorModel } from './EditorModel';
import { EditorTab } from './EditorTab';

/** Horizontal, scrollable editor tabs with dirty markers and close buttons. */
@ComponentV2
export struct TabStrip {
  @Param @Require model: EditorModel;

  @Builder
  tabMenu(tab: EditorTab) {
    Menu() {
      MenuItem({ content: $r('app.string.tab_close') }).onClick(() => this.model.close(tab.id))
      MenuItem({ content: $r('app.string.tab_close_others') }).onClick(() => this.model.closeOthers(tab.id))
      MenuItem({ content: $r('app.string.tab_close_all') }).onClick(() => this.model.closeAll())
    }
  }

  @Builder
  tabItem(tab: EditorTab) {
    Row({ space: $r('app.float.space_xs') }) {
      Image(tab.isDiff ? $r('app.media.ic_diff') : $r('app.media.ic_file'))
        .width($r('app.float.icon_size_small'))
        .height($r('app.float.icon_size_small'))
        .fillColor(tab.id === this.model.activeId ? $r('app.color.icon_active') : $r('app.color.icon'))
      Text(tab.title)
        .fontSize($r('app.float.font_s'))
        .fontColor(tab.id === this.model.activeId ? $r('app.color.text_strong') : $r('app.color.text_secondary'))
        .fontStyle(tab.isDiff ? FontStyle.Italic : FontStyle.Normal)
        .maxLines(UiConst.MAX_LINES_TITLE)
      Stack() {
        if (tab.dirty) {
          Circle()
            .width($r('app.float.dirty_dot_size'))
            .height($r('app.float.dirty_dot_size'))
            .fill($r('app.color.text_primary'))
        } else {
          Image($r('app.media.ic_close'))
            .width($r('app.float.icon_size_small'))
            .height($r('app.float.icon_size_small'))
            .fillColor($r('app.color.icon'))
        }
      }
      .width($r('app.float.tab_close_size'))
      .height($r('app.float.tab_close_size'))
      .borderRadius($r('app.float.radius_s'))
      .onClick(() => this.model.close(tab.id))
      .accessibilityText($r('app.string.tab_close'))
    }
    .height(UiConst.FULL)
    .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_xs') })
    .backgroundColor(tab.id === this.model.activeId ? $r('app.color.tab_active_bg') : $r('app.color.tab_bg'))
    .border({
      width: { right: $r('app.float.border_width'), top: $r('app.float.tab_indicator_width') },
      color: {
        right: $r('app.color.border'),
        top: tab.id === this.model.activeId ? $r('app.color.accent') : Color.Transparent
      }
    })
    .onClick(() => this.model.activate(tab.id))
    .bindContextMenu(this.tabMenu(tab), ResponseType.RightClick)
    .bindContextMenu(this.tabMenu(tab), ResponseType.LongPress)
  }

  build() {
    List() {
      ForEach(this.model.tabs, (tab: EditorTab) => {
        ListItem() {
          this.tabItem(tab)
        }
        .height(UiConst.FULL)
      }, (tab: EditorTab) => tab.id)
    }
    .listDirection(Axis.Horizontal)
    .scrollBar(BarState.Off)
    .width(UiConst.FULL)
    .height(layoutState.isPhone ? $r('app.float.tab_height_touch') : $r('app.float.tab_height'))
    .backgroundColor($r('app.color.tab_bg'))
    .border({ width: { bottom: $r('app.float.border_width') }, color: $r('app.color.border') })
  }
}
