import { UiConst } from '../../components/UiConst';
import { ActionButton, ActionStyle } from '../../components/ActionButton';
import { layoutState } from '../app/LayoutState';
import { CommandId } from '../commands/CommandService';
import { EditorModel } from './EditorModel';
import { EditorWebView } from './EditorWebView';
import { TabStrip } from './TabStrip';

interface ShortcutHint {
  label: Resource;
  keys: string;
}

/** Tabs + editor surface. Shows shortcut hints (or buttons on touch screens) when nothing is open. */
@ComponentV2
export struct EditorPane {
  @Param @Require model: EditorModel;
  @Event onCommand: (id: string) => void = () => {
  };

  private hints(): ShortcutHint[] {
    return [
      { label: $r('app.string.cmd_quick_open'), keys: 'Ctrl+P' },
      { label: $r('app.string.cmd_palette'), keys: 'Ctrl+Shift+P' },
      { label: $r('app.string.cmd_toggle_terminal'), keys: 'Ctrl+`' },
      { label: $r('app.string.cmd_show_search'), keys: 'Ctrl+Shift+F' },
    ];
  }

  @Builder
  emptyState() {
    Column({ space: $r('app.float.space_m') }) {
      Image($r('app.media.ic_logo'))
        .width($r('app.float.empty_logo_size'))
        .height($r('app.float.empty_logo_size'))
        .fillColor($r('app.color.watermark'))
      if (layoutState.isDesktop) {
        ForEach(this.hints(), (h: ShortcutHint) => {
          Row({ space: $r('app.float.space_l') }) {
            Text(h.label)
              .fontSize($r('app.float.font_s'))
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.End)
              .width($r('app.float.hint_label_width'))
            Text(h.keys)
              .fontSize($r('app.float.font_s'))
              .fontColor($r('app.color.text_secondary'))
              .padding({ left: $r('app.float.space_xs'), right: $r('app.float.space_xs') })
              .backgroundColor($r('app.color.keycap_bg'))
              .borderRadius($r('app.float.radius_s'))
          }
        }, (h: ShortcutHint) => h.keys)
      } else {
        ActionButton({
          text: $r('app.string.cmd_quick_open'), icon: $r('app.media.ic_search'), kind: ActionStyle.SECONDARY,
          onTap: () => this.onCommand(CommandId.QUICK_OPEN)
        })
        ActionButton({
          text: $r('app.string.cmd_new_file'), icon: $r('app.media.ic_new_file'), kind: ActionStyle.SECONDARY,
          onTap: () => this.onCommand(CommandId.NEW_FILE)
        })
      }
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.editor_bg'))
  }

  build() {
    Column() {
      if (this.model.tabs.length > 0) {
        TabStrip({ model: this.model })
      }
      Stack() {
        // The web view always exists so it's ready the moment a file opens.
        EditorWebView({ model: this.model })
        if (this.model.tabs.length === 0) {
          this.emptyState()
        }
      }
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .backgroundColor($r('app.color.editor_bg'))
  }
}
