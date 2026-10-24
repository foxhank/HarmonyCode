import { Splitter } from '../../components/Splitter';
import { UiConst } from '../../components/UiConst';
import { layoutState } from '../app/LayoutState';
import { ActivityBar } from './ActivityBar';
import { EditorArea } from './EditorArea';
import { SideBar } from './SideBar';
import { Workspace } from './Workspace';

/**
 * Tablet and desktop body: activity bar, side bar, editor area.
 * Desktop docks the side bar beside the editor; tablet slides it over the editor.
 */
@ComponentV2
export struct WideLayout {
  @Param @Require ws: Workspace;
  private dragBase: number = 0;

  private overlayWidth(): number {
    return Math.min(this.ws.ui.sidebarWidth, layoutState.width * UiConst.OVERLAY_SIDEBAR_RATIO);
  }

  @Builder
  docked() {
    Row() {
      if (this.ws.ui.sidebarVisible) {
        SideBar({ ws: this.ws, view: this.ws.ui.sideView })
          .width(this.ws.ui.sidebarWidth)
        Splitter({
          vertical: true,
          onStart: () => {
            this.dragBase = this.ws.ui.sidebarWidth;
          },
          onMove: (offset: number) => this.ws.ui.resizeSidebar(this.dragBase + offset)
        })
      }
      EditorArea({ ws: this.ws })
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
  }

  @Builder
  sliding() {
    Stack({ alignContent: Alignment.Start }) {
      EditorArea({ ws: this.ws })
      if (this.ws.ui.sidebarVisible) {
        Column()
          .width(UiConst.FULL)
          .height(UiConst.FULL)
          .backgroundColor($r('app.color.scrim'))
          .onClick(() => this.ws.ui.toggleSidebar())
          .transition(TransitionEffect.OPACITY.animation({ duration: UiConst.ANIM_FAST_MS }))
        SideBar({ ws: this.ws, view: this.ws.ui.sideView })
          .width(this.overlayWidth())
          .height(UiConst.FULL)
          .shadow(ShadowStyle.OUTER_DEFAULT_MD)
          .zIndex(UiConst.Z_OVERLAY)
          .transition(TransitionEffect.move(TransitionEdge.START)
            .animation({ duration: UiConst.ANIM_NORMAL_MS }))
      }
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
  }

  build() {
    Row() {
      ActivityBar({ ws: this.ws })
      Column() {
        if (layoutState.isDesktop) {
          this.docked()
        } else {
          this.sliding()
        }
      }
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      .height(UiConst.FULL)
      .clip(true)
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
  }
}
