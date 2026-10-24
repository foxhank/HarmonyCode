import { IconButton } from './IconButton';
import { UiConst } from './UiConst';

/** Title bar for full-screen pages: back button, title, trailing actions. */
@ComponentV2
export struct PageHeader {
  @Param @Require title: ResourceStr;
  @Event onBack: () => void = () => {
  };
  @BuilderParam trailing: () => void = noTrailing;

  build() {
    Row() {
      IconButton({
        icon: $r('app.media.ic_arrow_back'),
        label: $r('app.string.action_back'),
        buttonSize: $r('app.float.icon_button_size_touch'),
        onTap: () => this.onBack()
      })
      Text(this.title)
        .fontSize($r('app.float.font_xl'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: $r('app.float.space_s') })
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        .maxLines(UiConst.MAX_LINES_TITLE)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      this.trailing()
    }
    .width(UiConst.FULL)
    .height($r('app.float.page_header_height'))
    .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_l') })
  }
}

@Builder
function noTrailing() {
}
