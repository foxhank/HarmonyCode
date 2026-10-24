import { UiConst } from './UiConst';

/** Centered icon + title + message, with an optional action area. */
@ComponentV2
export struct EmptyState {
  @Param icon: Resource | undefined = undefined;
  @Param @Require title: ResourceStr;
  @Param message: ResourceStr = '';
  @BuilderParam action: () => void = noAction;

  build() {
    Column({ space: $r('app.float.space_m') }) {
      if (this.icon !== undefined) {
        Image(this.icon)
          .width($r('app.float.empty_icon_size'))
          .height($r('app.float.empty_icon_size'))
          .fillColor($r('app.color.icon_muted'))
      }
      Text(this.title)
        .fontSize($r('app.float.font_l'))
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
      Text(this.message)
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(UiConst.MAX_LINES_BODY)
      this.action()
    }
    .padding($r('app.float.space_xl'))
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

@Builder
function noAction() {
}
