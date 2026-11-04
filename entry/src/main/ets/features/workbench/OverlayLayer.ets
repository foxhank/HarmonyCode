import { IconButton } from '../../components/IconButton';
import { UiConst } from '../../components/UiConst';
import { layoutState } from '../app/LayoutState';
import { QuickOpenView } from '../commands/QuickOpenView';
import { BranchPicker } from '../scm/BranchPicker';
import { SettingsPanel } from '../settings/SettingsPanel';
import { OverlayId } from './WorkbenchState';
import { Workspace } from './Workspace';

/** Floating layers over the workbench: quick open, branch picker, settings. */
@ComponentV2
export struct OverlayLayer {
  @Param @Require ws: Workspace;

  private close(): void {
    this.ws.ui.closeOverlay();
  }

  @Builder
  settingsCard() {
    Column() {
      Row() {
        Text($r('app.string.settings_title'))
          .fontSize($r('app.float.font_l'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        IconButton({
          icon: $r('app.media.ic_close'), label: $r('app.string.action_close'),
          buttonSize: layoutState.isPhone ? $r('app.float.icon_button_size_touch') : $r('app.float.icon_button_size'),
          onTap: () => this.close()
        })
      }
      .width(UiConst.FULL)
      .height($r('app.float.page_header_height'))
      .padding({ left: $r('app.float.space_l'), right: $r('app.float.space_s') })
      .border({ width: { bottom: $r('app.float.border_width') }, color: $r('app.color.border') })

      SettingsPanel({ initialCategory: this.ws.ui.settingsCategory })
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
    }
    .width(layoutState.isPhone ? UiConst.FULL : $r('app.float.settings_overlay_width'))
    .height(layoutState.isPhone ? UiConst.FULL : UiConst.SETTINGS_OVERLAY_HEIGHT)
    .constraintSize({ maxWidth: layoutState.isPhone ? UiConst.FULL : UiConst.FLOATING_MAX_WIDTH })
    .backgroundColor($r('app.color.dialog_bg'))
    .borderRadius(layoutState.isPhone ? 0 : $r('app.float.radius_l'))
    .border({ width: layoutState.isPhone ? 0 : $r('app.float.border_width'), color: $r('app.color.border') })
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
    .clip(true)
  }

  build() {
    if (this.ws.ui.overlay !== OverlayId.NONE) {
      Stack({ alignContent: this.ws.ui.overlay === OverlayId.SETTINGS ? Alignment.Center : Alignment.Top }) {
        Column()
          .width(UiConst.FULL)
          .height(UiConst.FULL)
          .backgroundColor($r('app.color.scrim'))
          .onClick(() => this.close())
        Column() {
          if (this.ws.ui.overlay === OverlayId.QUICK_OPEN) {
            QuickOpenView({ model: this.ws.quickOpen, onClose: () => this.close() })
          } else if (this.ws.ui.overlay === OverlayId.BRANCHES) {
            BranchPicker({ model: this.ws.scm, onClose: () => this.close() })
          } else if (this.ws.ui.overlay === OverlayId.SETTINGS) {
            this.settingsCard()
          }
        }
        .margin({ top: this.ws.ui.overlay === OverlayId.SETTINGS ? 0 : $r('app.float.overlay_top_margin') })
      }
      .width(UiConst.FULL)
      .height(UiConst.FULL)
      .zIndex(UiConst.Z_OVERLAY)
    }
  }
}
