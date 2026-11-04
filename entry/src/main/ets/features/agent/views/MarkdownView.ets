import { LengthMetrics } from '@kit.ArkUI';
import { MONO_FONT } from '../../../components/Fonts';
import { UiConst } from '../../../components/UiConst';
import { BlockKind, Markdown, MdBlock, MdSpan, SpanKind } from '../markdown/Markdown';

/** Renders agent Markdown with native text (selectable, themed). */
@ComponentV2
export struct MarkdownView {
  @Param @Require text: string;

  @Computed
  get blocks(): MdBlock[] {
    return Markdown.parse(this.text);
  }

  private headingSize(level: number): Resource {
    return level <= 1 ? $r('app.float.font_xl') : (level === 2 ? $r('app.float.font_l') : $r('app.float.font_m'));
  }

  @Builder
  spans(spans: MdSpan[], size: Resource, weight: FontWeight) {
    Text() {
      ForEach(spans, (s: MdSpan) => {
        if (s.kind === SpanKind.CODE) {
          Span(s.text)
            .fontFamily(MONO_FONT)
            .fontSize($r('app.float.font_s'))
            .fontColor($r('app.color.code_text'))
            .textBackgroundStyle({ color: $r('app.color.code_bg'), radius: $r('app.float.radius_s') })
        } else {
          Span(s.text)
            .fontSize(size)
            .fontWeight(s.kind === SpanKind.BOLD ? FontWeight.Bold : weight)
            .fontStyle(s.kind === SpanKind.ITALIC ? FontStyle.Italic : FontStyle.Normal)
            .fontColor(s.kind === SpanKind.LINK ? $r('app.color.text_link') : $r('app.color.text_primary'))
        }
      }, (s: MdSpan, i: number) => i + ':' + s.kind + ':' + s.text)
    }
    .width(UiConst.FULL)
    .lineSpacing(LengthMetrics.vp(3))
    .copyOption(CopyOptions.LocalDevice)
  }

  @Builder
  codeBlock(b: MdBlock) {
    Column() {
      if (b.lang.length > 0) {
        Text(b.lang)
          .fontSize($r('app.float.font_xxs'))
          .fontColor($r('app.color.text_muted'))
          .width(UiConst.FULL)
          .padding({ left: $r('app.float.space_s'), top: $r('app.float.space_xs') })
      }
      Scroll() {
        Text(b.code)
          .fontFamily(MONO_FONT)
          .fontSize($r('app.float.font_s'))
          .fontColor($r('app.color.code_text'))
          .copyOption(CopyOptions.LocalDevice)
          .padding($r('app.float.space_s'))
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width(UiConst.FULL)
      .align(Alignment.Start)
    }
    .width(UiConst.FULL)
    .backgroundColor($r('app.color.code_bg'))
    .borderRadius($r('app.float.radius_m'))
  }

  build() {
    Column({ space: $r('app.float.space_s') }) {
      ForEach(this.blocks, (b: MdBlock) => {
        if (b.kind === BlockKind.CODE) {
          this.codeBlock(b)
        } else if (b.kind === BlockKind.HEADING) {
          this.spans(b.spans, this.headingSize(b.level), FontWeight.Bold)
        } else if (b.kind === BlockKind.LIST_ITEM) {
          Row({ space: $r('app.float.space_xs') }) {
            Text(b.marker)
              .fontSize($r('app.float.font_m'))
              .fontColor($r('app.color.text_secondary'))
              .constraintSize({ minWidth: $r('app.float.list_marker_width') })
            Column() {
              this.spans(b.spans, $r('app.float.font_m'), FontWeight.Normal)
            }
            .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
          }
          .width(UiConst.FULL)
          .alignItems(VerticalAlign.Top)
          .padding({ left: b.level * UiConst.TREE_INDENT })
        } else if (b.kind === BlockKind.QUOTE) {
          Column() {
            this.spans(b.spans, $r('app.float.font_m'), FontWeight.Normal)
          }
          .width(UiConst.FULL)
          .padding({ left: $r('app.float.space_s') })
          .border({ width: { left: $r('app.float.quote_bar_width') }, color: { left: $r('app.color.border') } })
        } else if (b.kind === BlockKind.RULE) {
          Divider().color($r('app.color.border'))
        } else {
          this.spans(b.spans, $r('app.float.font_m'), FontWeight.Normal)
        }
      }, (b: MdBlock, i: number) => i + ':' + b.kind + ':' + b.code.length + ':' + b.spans.length +
        ':' + (b.spans.length > 0 ? b.spans[b.spans.length - 1].text.length : 0))
    }
    .width(UiConst.FULL)
    .alignItems(HorizontalAlign.Start)
  }
}
