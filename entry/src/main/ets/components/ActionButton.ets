import { UiConst } from './UiConst';

export enum ActionStyle {
  PRIMARY = 'primary',
  SECONDARY = 'secondary',
  DANGER = 'danger'
}

/** Text button in one of the app's three styles, with an optional leading icon. */
@ComponentV2
export struct ActionButton {
  @Param @Require text: ResourceStr;
  @Param icon: Resource | undefined = undefined;
  @Param kind: string = ActionStyle.PRIMARY;
  @Param isEnabled: boolean = true;
  @Param stretch: boolean = false;
  @Param buttonHeight: Length = $r('app.float.button_height');
  @Event onTap: () => void = () => {
  };

  private bg(): ResourceColor {
    if (this.kind === ActionStyle.PRIMARY) {
      return $r('app.color.button_primary_bg');
    }
    if (this.kind === ActionStyle.DANGER) {
      return $r('app.color.danger');
    }
    return $r('app.color.button_secondary_bg');
  }

  private fg(): ResourceColor {
    return this.kind === ActionStyle.SECONDARY ? $r('app.color.button_secondary_text') : $r('app.color.text_on_accent');
  }

  build() {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Row({ space: $r('app.float.space_s') }) {
        if (this.icon !== undefined) {
          Image(this.icon)
            .width($r('app.float.icon_size_small'))
            .height($r('app.float.icon_size_small'))
            .fillColor(this.fg())
        }
        Text(this.text)
          .fontSize($r('app.float.font_m'))
          .fontColor(this.fg())
          .maxLines(UiConst.MAX_LINES_TITLE)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m') })
      .justifyContent(FlexAlign.Center)
    }
    .height(this.buttonHeight)
    .width(this.stretch ? UiConst.FULL : undefined)
    .backgroundColor(this.bg())
    .shadow(this.kind === ActionStyle.PRIMARY && this.isEnabled ?
      { radius: UiConst.SHADOW_SOFT_RADIUS, color: $r('app.color.bubble_shadow'), offsetY: UiConst.SHADOW_SOFT_OFFSET } :
      { radius: 0, color: Color.Transparent })
    .enabled(this.isEnabled)
    .opacity(this.isEnabled ? 1 : UiConst.DISABLED_OPACITY)
    .onClick(() => this.onTap())
  }
}
