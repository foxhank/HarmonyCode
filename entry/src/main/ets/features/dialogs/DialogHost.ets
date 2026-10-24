import { ActionButton, ActionStyle } from '../../components/ActionButton';
import { InputModifier } from '../../components/Modifiers';
import { UiConst } from '../../components/UiConst';
import { ButtonRole, DialogButton, DialogKind, DialogModel } from './DialogModel';

/** Renders the active prompt/confirm dialog over the whole app. */
@ComponentV2
export struct DialogHost {
  @Param @Require model: DialogModel;
  private inputStyle: InputModifier = new InputModifier();

  private styleFor(b: DialogButton): string {
    if (b.role === ButtonRole.PRIMARY) {
      return ActionStyle.PRIMARY;
    }
    return b.role === ButtonRole.DANGER ? ActionStyle.DANGER : ActionStyle.SECONDARY;
  }

  build() {
    if (this.model.visible) {
      Stack() {
        Column()
          .width(UiConst.FULL)
          .height(UiConst.FULL)
          .backgroundColor($r('app.color.scrim'))
          .onClick(() => this.model.cancel())
        Column({ space: $r('app.float.space_m') }) {
          Text(this.model.title)
            .fontSize($r('app.float.font_l'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width(UiConst.FULL)
          if (this.model.kind === DialogKind.CONFIRM) {
            Text(this.model.message)
              .fontSize($r('app.float.font_m'))
              .fontColor($r('app.color.text_secondary'))
              .width(UiConst.FULL)
          } else {
            TextInput({ text: this.model.value, placeholder: this.model.placeholder })
              .attributeModifier(this.inputStyle)
              .width(UiConst.FULL)
              .defaultFocus(true)
              .onChange((v: string) => this.model.setValue(v))
              .onSubmit(() => this.model.press(1))
            if (this.model.error.length > 0) {
              Text(this.model.error)
                .fontSize($r('app.float.font_s'))
                .fontColor($r('app.color.danger'))
                .width(UiConst.FULL)
            }
          }
          Row({ space: $r('app.float.space_s') }) {
            Blank()
            ForEach(this.model.buttons, (b: DialogButton, i: number) => {
              ActionButton({ text: b.label, kind: this.styleFor(b), onTap: () => this.model.press(i) })
            }, (b: DialogButton, i: number) => i.toString())
          }
          .width(UiConst.FULL)
          .margin({ top: $r('app.float.space_s') })
        }
        .width($r('app.float.dialog_width'))
        .constraintSize({ maxWidth: UiConst.FLOATING_MAX_WIDTH })
        .padding($r('app.float.space_l'))
        .backgroundColor($r('app.color.dialog_bg'))
        .borderRadius($r('app.float.radius_l'))
        .border({ width: $r('app.float.border_width'), color: $r('app.color.border') })
        .shadow(ShadowStyle.OUTER_DEFAULT_MD)
      }
      .width(UiConst.FULL)
      .height(UiConst.FULL)
      .zIndex(UiConst.Z_DIALOG)
    }
  }
}
