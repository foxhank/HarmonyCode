import { UiConst } from './UiConst';

/** Upper-case section title (e.g. "EXPLORER") with trailing action buttons. */
@ComponentV2
export struct SectionHeader {
  @Param @Require title: ResourceStr;
  @Param subtitle: string = '';
  @BuilderParam actions: () => void = emptyActions;

  build() {
    Row() {
      Text(this.title)
        .fontSize($r('app.float.font_xs'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .textCase(TextCase.UpperCase)
        .maxLines(UiConst.MAX_LINES_TITLE)
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.text_muted'))
          .margin({ left: $r('app.float.space_s') })
          .maxLines(UiConst.MAX_LINES_TITLE)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      } else {
        Blank()
      }
      Row() {
        this.actions()
      }
    }
    .width(UiConst.FULL)
    .height($r('app.float.section_header_height'))
    .padding({ left: $r('app.float.space_l'), right: $r('app.float.space_xs') })
  }
}

@Builder
function emptyActions() {
}
