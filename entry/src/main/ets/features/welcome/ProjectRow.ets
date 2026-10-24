import { Strings } from '../../core/common/Strings';
import { TimeFormat } from '../../core/common/TimeFormat';
import { Catalog } from '../../core/project/Catalog';
import { ProjectInfo } from '../../core/project/ProjectInfo';
import { TemplateBadge } from '../../components/TemplateBadge';
import { UiConst } from '../../components/UiConst';
import { CatalogText } from '../app/CatalogText';

/** One entry in the recent-projects list, with a context menu. */
@ComponentV2
export struct ProjectRow {
  @Param @Require project: ProjectInfo;
  @Param touch: boolean = false;
  @Event onOpen: () => void = () => {
  };
  @Event onRemove: () => void = () => {
  };
  @Event onDelete: () => void = () => {
  };

  @Builder
  menu() {
    Menu() {
      MenuItem({ content: $r('app.string.action_open') }).onClick(() => this.onOpen())
      MenuItem({ content: $r('app.string.welcome_remove_from_list') }).onClick(() => this.onRemove())
      MenuItem({ content: $r('app.string.welcome_delete_from_disk') }).onClick(() => this.onDelete())
    }
  }

  build() {
    Row({ space: $r('app.float.space_m') }) {
      TemplateBadge({
        label: Catalog.template(this.project.templateId)?.badge ?? '',
        color: Catalog.template(this.project.templateId)?.color ?? '',
      })
      Column({ space: $r('app.float.space_xxs') }) {
        Text(this.project.name)
          .fontSize($r('app.float.font_m'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(UiConst.MAX_LINES_TITLE)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(Strings.get('welcome_project_meta', CatalogText.envName(this.project.envId),
          TimeFormat.relative(this.project.lastOpened)))
          .fontSize($r('app.float.font_s'))
          .fontColor($r('app.color.text_secondary'))
          .maxLines(UiConst.MAX_LINES_TITLE)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
    }
    .width(UiConst.FULL)
    .height(this.touch ? $r('app.float.list_row_touch_tall') : $r('app.float.list_row_tall'))
    .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m') })
    .borderRadius($r('app.float.radius_m'))
    .stateStyles({
      normal: { .backgroundColor(Color.Transparent) },
      pressed: { .backgroundColor($r('app.color.hover_bg')) }
    })
    .onClick(() => this.onOpen())
    .bindContextMenu(this.menu, ResponseType.RightClick)
    .bindContextMenu(this.menu, ResponseType.LongPress)
  }
}
