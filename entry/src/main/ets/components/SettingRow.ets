import { UiConst } from './UiConst';

/** Label on the left, control on the right. */
@ComponentV2
export struct SettingRow {
  @Param @Require label: ResourceStr;
  @BuilderParam control: () => void = noControl;

  build() {
    Row() {
      Text(this.label)
        .fontSize($r('app.float.font_m'))
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      this.control()
    }
    .width(UiConst.FULL)
  }
}

@Builder
function noControl() {
}
