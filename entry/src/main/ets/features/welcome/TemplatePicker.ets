import { TemplateDef } from '../../core/project/Catalog';
import { TemplateBadge } from '../../components/TemplateBadge';
import { UiConst } from '../../components/UiConst';
import { CatalogText } from '../app/CatalogText';

/** Template list: a vertical list on wide screens, a two-column grid on phones. */
@ComponentV2
export struct TemplatePicker {
  @Param @Require templates: TemplateDef[];
  @Param @Require selectedId: string;
  @Param compact: boolean = false;
  @Event onSelect: (id: string) => void = () => {
  };

  @Builder
  item(t: TemplateDef) {
    Row({ space: $r('app.float.space_m') }) {
      TemplateBadge({ label: t.badge, color: t.color, badgeSize: $r('app.float.badge_size_medium') })
      Column() {
        Text(CatalogText.templateName(t.id))
          .fontSize($r('app.float.font_m'))
          .fontColor($r('app.color.text_primary'))
          .maxLines(UiConst.MAX_LINES_TITLE)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (!this.compact) {
          Text(CatalogText.templateDetail(t.id))
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.text_secondary'))
            .maxLines(UiConst.MAX_LINES_TITLE)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
    }
    .width(UiConst.FULL)
    .height($r('app.float.list_row_touch_tall'))
    .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m') })
    .borderRadius($r('app.float.radius_m'))
    .backgroundColor(t.id === this.selectedId ? $r('app.color.selected_bg') : Color.Transparent)
    .onClick(() => this.onSelect(t.id))
  }

  build() {
    if (this.compact) {
      Grid() {
        ForEach(this.templates, (t: TemplateDef) => {
          GridItem() {
            this.item(t)
          }
        }, (t: TemplateDef) => t.id)
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap($r('app.float.space_s'))
      .rowsGap($r('app.float.space_s'))
      .width(UiConst.FULL)
      .maxCount(this.templates.length)
    } else {
      List() {
        ForEach(this.templates, (t: TemplateDef) => {
          ListItem() {
            this.item(t)
          }
          .padding({ bottom: $r('app.float.space_xxs') })
        }, (t: TemplateDef) => t.id)
      }
      .width(UiConst.FULL)
      .height(UiConst.FULL)
    }
  }
}
