import { MONO_FONT } from '../../../components/Fonts';
import { UiConst } from '../../../components/UiConst';

/** Lines shown before the rest is collapsed. */
const MAX_LINES: number = 400;

class DiffLine {
  index: number;
  text: string;
  tag: string;

  constructor(index: number, text: string) {
    this.index = index;
    this.text = text;
    this.tag = text.startsWith('@@') ? '@' : (text.startsWith('+++') || text.startsWith('---') ? 'h' : text.charAt(0));
  }
}

/** A unified diff with added/removed lines colored. */
@ComponentV2
export struct DiffView {
  @Param @Require diff: string;

  @Computed
  get lines(): DiffLine[] {
    const all = this.diff.split('\n');
    const out: DiffLine[] = [];
    for (let i = 0; i < Math.min(all.length, MAX_LINES); i++) {
      out.push(new DiffLine(i, all[i]));
    }
    return out;
  }

  @Computed
  get hidden(): number {
    return Math.max(0, this.diff.split('\n').length - MAX_LINES);
  }

  private bg(tag: string): ResourceColor {
    if (tag === '+') {
      return $r('app.color.diff_added_bg');
    }
    if (tag === '-') {
      return $r('app.color.diff_removed_bg');
    }
    return Color.Transparent;
  }

  private fg(tag: string): ResourceColor {
    if (tag === '@' || tag === 'h') {
      return $r('app.color.text_muted');
    }
    return $r('app.color.code_text');
  }

  build() {
    Scroll() {
      Column() {
        ForEach(this.lines, (l: DiffLine) => {
          Text(l.text.length > 0 ? l.text : ' ')
            .fontFamily(MONO_FONT)
            .fontSize($r('app.float.font_xs'))
            .fontColor(this.fg(l.tag))
            .backgroundColor(this.bg(l.tag))
            .constraintSize({ minWidth: UiConst.FULL })
            .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s') })
            .maxLines(1)
        }, (l: DiffLine) => l.index + ':' + l.text)
        if (this.hidden > 0) {
          Text($r('app.string.agent_diff_more', this.hidden))
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.text_muted'))
            .padding($r('app.float.space_s'))
        }
      }
      .alignItems(HorizontalAlign.Start)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width(UiConst.FULL)
    .align(Alignment.Start)
    .backgroundColor($r('app.color.code_bg'))
    .borderRadius($r('app.float.radius_s'))
  }
}
