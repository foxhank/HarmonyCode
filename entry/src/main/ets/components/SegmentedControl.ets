import { UiConst } from './UiConst';

export interface SegmentOption {
  value: string;
  label: ResourceStr;
}

/** Row of mutually exclusive options. */
@ComponentV2
export struct SegmentedControl {
  @Param @Require options: SegmentOption[];
  @Param @Require selected: string;
  @Event onSelect: (value: string) => void = () => {
  };

  build() {
    Row() {
      ForEach(this.options, (o: SegmentOption) => {
        Text(o.label)
          .fontSize($r('app.float.font_s'))
          .fontColor(o.value === this.selected ? $r('app.color.text_on_accent') : $r('app.color.text_primary'))
          .backgroundColor(o.value === this.selected ? $r('app.color.accent') : Color.Transparent)
          .borderRadius($r('app.float.radius_s'))
          .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m') })
          .height(UiConst.FULL)
          .textAlign(TextAlign.Center)
          .onClick(() => this.onSelect(o.value))
      }, (o: SegmentOption) => o.value)
    }
    .height($r('app.float.button_height'))
    .padding($r('app.float.space_xxs'))
    .backgroundColor($r('app.color.input_bg'))
    .borderRadius($r('app.float.radius_s'))
  }
}
