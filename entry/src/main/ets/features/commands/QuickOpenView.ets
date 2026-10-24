import { KeyCode } from '@kit.InputKit';
import { Strings } from '../../core/common/Strings';
import { InputModifier } from '../../components/Modifiers';
import { UiConst } from '../../components/UiConst';
import { MONO_FONT } from '../../components/Fonts';
import { QuickItem, QuickKind, QuickOpenModel } from './QuickOpenModel';

/** VS Code-style quick pick: input on top, results below, keyboard navigable. */
@ComponentV2
export struct QuickOpenView {
  @Param @Require model: QuickOpenModel;
  @Event onClose: () => void = () => {
  };
  private inputStyle: InputModifier = new InputModifier();

  private iconFor(item: QuickItem): Resource {
    if (item.kind === QuickKind.FILE) {
      return $r('app.media.ic_file');
    }
    return item.kind === QuickKind.LINE ? $r('app.media.ic_goto') : $r('app.media.ic_command');
  }

  private onKey(e: KeyEvent): void {
    if (e.type !== KeyType.Down) {
      return;
    }
    if (e.keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
      this.model.move(1);
    } else if (e.keyCode === KeyCode.KEYCODE_DPAD_UP) {
      this.model.move(-1);
    } else if (e.keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.onClose();
    }
  }

  build() {
    Column() {
      TextInput({ text: this.model.query, placeholder: Strings.get(this.model.placeholderKey) })
        .attributeModifier(this.inputStyle)
        .width(UiConst.FULL)
        .defaultFocus(true)
        .onChange((v: string) => this.model.setQuery(v))
        .onSubmit(() => this.model.accept())
        .onKeyEvent((e: KeyEvent) => this.onKey(e))
        .margin($r('app.float.space_s'))
      List() {
        ForEach(this.model.items, (item: QuickItem, i: number) => {
          ListItem() {
            Row({ space: $r('app.float.space_s') }) {
              Image(this.iconFor(item))
                .width($r('app.float.icon_size_small'))
                .height($r('app.float.icon_size_small'))
                .fillColor($r('app.color.icon'))
              Text(item.label)
                .fontSize($r('app.float.font_m'))
                .fontColor($r('app.color.text_primary'))
                .maxLines(UiConst.MAX_LINES_TITLE)
              Text(item.detail)
                .fontSize($r('app.float.font_xs'))
                .fontFamily(item.kind === QuickKind.COMMAND ? MONO_FONT : undefined)
                .fontColor($r('app.color.text_muted'))
                .maxLines(UiConst.MAX_LINES_TITLE)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
                .textAlign(item.kind === QuickKind.COMMAND ? TextAlign.End : TextAlign.Start)
            }
            .width(UiConst.FULL)
            .height($r('app.float.list_row_compact_touch'))
            .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m') })
            .backgroundColor(i === this.model.selected ? $r('app.color.selected_focus_bg') : Color.Transparent)
            .onClick(() => this.model.accept(i))
          }
        }, (item: QuickItem) => item.kind + item.id)
      }
      .constraintSize({ maxHeight: $r('app.float.popup_max_height') })
      .scrollBar(BarState.Auto)
      if (this.model.items.length === 0) {
        Text($r('app.string.quick_no_results'))
          .fontSize($r('app.float.font_s'))
          .fontColor($r('app.color.text_muted'))
          .padding($r('app.float.space_m'))
      }
    }
    .width($r('app.float.quick_open_width'))
    .constraintSize({ maxWidth: UiConst.FLOATING_MAX_WIDTH })
    .backgroundColor($r('app.color.dialog_bg'))
    .borderRadius($r('app.float.radius_l'))
    .border({ width: $r('app.float.border_width'), color: $r('app.color.border') })
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }
}
