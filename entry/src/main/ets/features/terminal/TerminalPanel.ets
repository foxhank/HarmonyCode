import { IconButton } from '../../components/IconButton';
import { UiConst } from '../../components/UiConst';
import { layoutState } from '../app/LayoutState';
import { ExtraKeys } from './ExtraKeys';
import { TerminalModel } from './TerminalModel';
import { TerminalWebView } from './TerminalWebView';

/** Bottom panel (desktop/tablet) or full screen (phone) with the integrated terminal. */
@ComponentV2
export struct TerminalPanel {
  @Param @Require model: TerminalModel;
  @Param maximized: boolean = false;
  @Event onRun: () => void = () => {
  };
  @Event onToggleMaximize: () => void = () => {
  };
  @Event onClose: () => void = () => {
  };

  build() {
    Column() {
      Row({ space: $r('app.float.space_xs') }) {
        Text($r('app.string.terminal_title'))
          .fontSize($r('app.float.font_xs'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .textCase(TextCase.UpperCase)
        Text(this.model.label)
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.text_muted'))
          .maxLines(UiConst.MAX_LINES_TITLE)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        IconButton({ icon: $r('app.media.ic_play'), label: $r('app.string.cmd_run'), onTap: () => this.onRun() })
        IconButton({ icon: $r('app.media.ic_clear'), label: $r('app.string.terminal_clear'),
          onTap: () => this.model.clear() })
        if (!layoutState.isPhone) {
          IconButton({
            icon: this.maximized ? $r('app.media.ic_restore') : $r('app.media.ic_maximize'),
            label: $r('app.string.terminal_maximize'),
            onTap: () => this.onToggleMaximize()
          })
          IconButton({ icon: $r('app.media.ic_close'), label: $r('app.string.terminal_hide'),
            onTap: () => this.onClose() })
        }
      }
      .width(UiConst.FULL)
      .height($r('app.float.section_header_height'))
      .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_xs') })

      TerminalWebView({ model: this.model })
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)

      if (!layoutState.isDesktop) {
        ExtraKeys({ model: this.model })
      }
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .backgroundColor($r('app.color.terminal_bg'))
  }
}
