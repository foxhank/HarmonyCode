import { UiConst } from './UiConst';

export interface SegmentOption {
  value: string;
  label: ResourceStr;
}

/**
 * Row of mutually exclusive options, HarmonyOS style: a soft capsule track with the selected
 * option raised on a light card. Scrolls sideways when the options don't fit.
 */
@ComponentV2
export struct SegmentedControl {
  @Param @Require options: SegmentOption[];
  @Param @Require selected: string;
  @Event onSelect: (value: string) => void = () => {
  };

  build() {
    Scroll() {
      Row() {
        ForEach(this.options, (o: SegmentOption) => {
          Text(o.label)
            .fontSize($r('app.float.font_s'))
            .fontWeight(o.value === this.selected ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(o.value === this.selected ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
            .backgroundColor(o.value === this.selected ? $r('app.color.card_bg') : Color.Transparent)
            .shadow(o.value === this.selected ? ShadowStyle.OUTER_DEFAULT_XS : { radius: 0, color: Color.Transparent })
            .borderRadius($r('app.float.radius_xl'))
            .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m') })
            .height(UiConst.FULL)
            .textAlign(TextAlign.Center)
            .maxLines(UiConst.MAX_LINES_TITLE)
            .animation({ duration: UiConst.ANIM_FAST_MS, curve: Curve.FastOutSlowIn })
            .onClick(() => this.onSelect(o.value))
            .accessibilitySelected(o.value === this.selected)
        }, (o: SegmentOption) => o.value)
      }
      .height($r('app.float.button_height'))
      .padding($r('app.float.space_xxs'))
      .backgroundColor($r('app.color.choice_bg'))
      .borderRadius($r('app.float.radius_xl'))
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .constraintSize({ maxWidth: UiConst.SEGMENT_MAX_WIDTH })
  }
}
