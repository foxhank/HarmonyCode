/** Colored square with a short label (language badge for templates and projects). */
@ComponentV2
export struct TemplateBadge {
  @Param @Require label: string;
  @Param @Require color: string;
  @Param badgeSize: Length = $r('app.float.badge_size_large');

  build() {
    Text(this.label)
      .width(this.badgeSize)
      .height(this.badgeSize)
      .textAlign(TextAlign.Center)
      .fontSize($r('app.float.font_s'))
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_on_accent'))
      .backgroundColor(this.color)
      .borderRadius($r('app.float.radius_m'))
  }
}
