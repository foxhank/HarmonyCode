import { IconButton } from './IconButton';

/** − value + control with bounds. */
@ComponentV2
export struct NumberStepper {
  @Param @Require value: number;
  @Param min: number = 0;
  @Param max: number = Number.MAX_SAFE_INTEGER;
  @Param step: number = 1;
  @Event onChange: (v: number) => void = () => {
  };

  build() {
    Row() {
      IconButton({
        icon: $r('app.media.ic_remove'), label: $r('app.string.action_decrease'), isEnabled: this.value > this.min,
        onTap: () => this.onChange(Math.max(this.min, this.value - this.step))
      })
      Text(this.value.toString())
        .fontSize($r('app.float.font_m'))
        .fontColor($r('app.color.text_primary'))
        .width($r('app.float.stepper_value_width'))
        .textAlign(TextAlign.Center)
      IconButton({
        icon: $r('app.media.ic_add'), label: $r('app.string.action_increase'), isEnabled: this.value < this.max,
        onTap: () => this.onChange(Math.min(this.max, this.value + this.step))
      })
    }
    .backgroundColor($r('app.color.input_bg'))
    .borderRadius($r('app.float.radius_s'))
  }
}
