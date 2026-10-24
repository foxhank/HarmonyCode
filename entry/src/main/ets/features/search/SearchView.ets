import { Strings } from '../../core/common/Strings';
import { SearchHit } from '../../core/search/TextSearch';
import { InputModifier } from '../../components/Modifiers';
import { SectionHeader } from '../../components/SectionHeader';
import { UiConst } from '../../components/UiConst';
import { MONO_FONT } from '../../components/Fonts';
import { layoutState } from '../app/LayoutState';
import { SearchGroup, SearchModel } from './SearchModel';

/** Find in files: query, options, grouped results. */
@ComponentV2
export struct SearchView {
  @Param @Require model: SearchModel;
  private inputStyle: InputModifier = new InputModifier();

  @Builder
  toggle(label: ResourceStr, on: boolean, a11y: Resource, onTap: () => void) {
    Text(label)
      .fontSize($r('app.float.font_s'))
      .fontFamily(MONO_FONT)
      .fontColor(on ? $r('app.color.text_on_accent') : $r('app.color.text_secondary'))
      .backgroundColor(on ? $r('app.color.accent') : Color.Transparent)
      .borderRadius($r('app.float.radius_s'))
      .padding({ left: $r('app.float.space_xs'), right: $r('app.float.space_xs') })
      .height($r('app.float.icon_button_size'))
      .accessibilityText(a11y)
      .onClick(onTap)
  }

  @Builder
  groupHeader(g: SearchGroup) {
    Row({ space: $r('app.float.space_s') }) {
      Image($r('app.media.ic_file'))
        .width($r('app.float.icon_size_small'))
        .height($r('app.float.icon_size_small'))
        .fillColor($r('app.color.file_icon'))
      Text(g.relPath)
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.text_primary'))
        .maxLines(UiConst.MAX_LINES_TITLE)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      Text(g.hits.length.toString())
        .fontSize($r('app.float.font_xs'))
        .fontColor($r('app.color.badge_text'))
        .backgroundColor($r('app.color.badge_bg'))
        .borderRadius($r('app.float.radius_l'))
        .padding({ left: $r('app.float.space_xs'), right: $r('app.float.space_xs') })
    }
    .width(UiConst.FULL)
    .height($r('app.float.tree_row_height'))
    .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m') })
    .backgroundColor($r('app.color.sidebar_bg'))
  }

  build() {
    Column() {
      SectionHeader({ title: $r('app.string.search_title') })
      Column({ space: $r('app.float.space_xs') }) {
        Row({ space: $r('app.float.space_xs') }) {
          TextInput({ text: this.model.query, placeholder: $r('app.string.search_placeholder') })
            .attributeModifier(this.inputStyle)
            .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
            .onChange((v: string) => this.model.setQuery(v))
            .onSubmit(() => this.model.run())
          this.toggle($r('app.string.search_match_case_short'), this.model.matchCase,
            $r('app.string.search_match_case'), () => this.model.toggleCase())
          this.toggle($r('app.string.search_regex_short'), this.model.regex,
            $r('app.string.search_regex'), () => this.model.toggleRegex())
        }
        if (this.model.invalid) {
          Text($r('app.string.search_invalid_regex'))
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.danger'))
        } else if (this.model.busy) {
          Text($r('app.string.search_searching'))
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.text_secondary'))
        } else if (this.model.query.length > 0) {
          Text(this.model.total === 0 ? Strings.get('search_no_results') :
          Strings.get('search_summary', Strings.plural('plural_results', this.model.total),
            Strings.plural('plural_files', this.model.groups.length)))
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m'), bottom: $r('app.float.space_s') })

      List() {
        ForEach(this.model.groups, (g: SearchGroup) => {
          ListItemGroup({ header: this.groupHeader(g) }) {
            ForEach(g.hits, (h: SearchHit) => {
              ListItem() {
                Row({ space: $r('app.float.space_s') }) {
                  Text(h.line.toString())
                    .fontSize($r('app.float.font_xs'))
                    .fontColor($r('app.color.text_muted'))
                    .width($r('app.float.line_number_width'))
                    .textAlign(TextAlign.End)
                  Text(h.preview)
                    .fontSize($r('app.float.font_s'))
                    .fontFamily(MONO_FONT)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(UiConst.MAX_LINES_TITLE)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
                }
                .width(UiConst.FULL)
                .height(layoutState.isDesktop ? $r('app.float.tree_row_height') : $r('app.float.list_row_touch'))
                .padding({ left: $r('app.float.space_l'), right: $r('app.float.space_m') })
                .onClick(() => this.model.open(h))
              }
            }, (h: SearchHit) => h.line + ':' + h.col)
          }
        }, (g: SearchGroup) => g.path)
      }
      .sticky(StickyStyle.Header)
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      .scrollBar(BarState.Auto)
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .backgroundColor($r('app.color.sidebar_bg'))
  }
}
