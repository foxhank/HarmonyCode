import { UiConst } from './UiConst';

/** Square, borderless button showing a recolorable SVG icon. */
@ComponentV2
export struct IconButton {
  @Param @Require icon: Resource;
  /** Accessibility label (also used as the tooltip on desktop). */
  @Param @Require label: Resource;
  @Param buttonSize: Length = $r('app.float.icon_button_size');
  @Param iconSize: Length = $r('app.float.icon_size');
  @Param color: ResourceColor = $r('app.color.icon');
  @Param activeColor: ResourceColor = $r('app.color.icon_active');
  @Param active: boolean = false;
  @Param isEnabled: boolean = true;
  @Event onTap: () => void = () => {
  };

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Image(this.icon)
        .width(this.iconSize)
        .height(this.iconSize)
        .fillColor(this.active ? this.activeColor : this.color)
        .objectFit(ImageFit.Contain)
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius($r('app.float.radius_s'))
    .enabled(this.isEnabled)
    .opacity(this.isEnabled ? 1 : UiConst.DISABLED_OPACITY)
    .accessibilityText(this.label)
    .onClick(() => this.onTap())
  }
}
