import { EmptyState } from '../../components/EmptyState';
import { IconButton } from '../../components/IconButton';
import { SectionHeader } from '../../components/SectionHeader';
import { UiConst } from '../../components/UiConst';
import { ActionButton, ActionStyle } from '../../components/ActionButton';
import { layoutState } from '../app/LayoutState';
import { gitColor } from '../scm/GitColors';
import { ExplorerModel, TreeRow } from './ExplorerModel';

/** File tree with VS Code-style actions and context menus. */
@ComponentV2
export struct ExplorerView {
  @Param @Require model: ExplorerModel;
  @Param projectName: string = '';

  @Builder
  headerActions() {
    IconButton({ icon: $r('app.media.ic_new_file'), label: $r('app.string.explorer_new_file'),
      onTap: () => this.model.newFile() })
    IconButton({ icon: $r('app.media.ic_new_folder'), label: $r('app.string.explorer_new_folder'),
      onTap: () => this.model.newFolder() })
    IconButton({ icon: $r('app.media.ic_refresh'), label: $r('app.string.action_refresh'),
      onTap: () => this.model.refresh() })
    IconButton({ icon: $r('app.media.ic_collapse'), label: $r('app.string.explorer_collapse_all'),
      onTap: () => this.model.collapseAll() })
  }

  @Builder
  rowMenu(row: TreeRow) {
    Menu() {
      if (row.isDir) {
        MenuItem({ content: $r('app.string.explorer_new_file') }).onClick(() => this.model.newFile(row.path))
        MenuItem({ content: $r('app.string.explorer_new_folder') }).onClick(() => this.model.newFolder(row.path))
      }
      MenuItem({ content: $r('app.string.explorer_rename') }).onClick(() => this.model.rename(row.path))
      MenuItem({ content: $r('app.string.action_delete') }).onClick(() => this.model.remove(row.path))
      MenuItem({ content: $r('app.string.explorer_copy_path') }).onClick(() => this.model.copyPath(row.path, false))
      MenuItem({ content: $r('app.string.explorer_copy_relative_path') })
        .onClick(() => this.model.copyPath(row.path, true))
    }
  }

  @Builder
  treeRow(row: TreeRow) {
    Row({ space: $r('app.float.space_xs') }) {
      if (row.isDir) {
        Image(row.expanded ? $r('app.media.ic_chevron_down') : $r('app.media.ic_chevron_right'))
          .width($r('app.float.icon_size_small'))
          .height($r('app.float.icon_size_small'))
          .fillColor($r('app.color.icon'))
      } else {
        Blank().width($r('app.float.icon_size_small'))
      }
      Image(row.isDir ? (row.expanded ? $r('app.media.ic_folder_open') : $r('app.media.ic_folder')) :
        $r('app.media.ic_file'))
        .width($r('app.float.icon_size_small'))
        .height($r('app.float.icon_size_small'))
        .fillColor(row.isDir ? $r('app.color.folder_icon') : $r('app.color.file_icon'))
      Text(row.name)
        .fontSize($r('app.float.font_m'))
        .fontColor(row.git.length > 0 ? gitColor(row.git) : $r('app.color.text_primary'))
        .maxLines(UiConst.MAX_LINES_TITLE)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      if (row.git.length > 0 && !row.isDir) {
        Text(row.git)
          .fontSize($r('app.float.font_s'))
          .fontColor(gitColor(row.git))
          .margin({ right: $r('app.float.space_s') })
      }
    }
    .width(UiConst.FULL)
    .height(layoutState.isDesktop ? $r('app.float.tree_row_height') : $r('app.float.list_row_touch'))
    .padding({ left: row.depth * UiConst.TREE_INDENT + UiConst.TREE_INDENT / 2 })
    .backgroundColor(row.path === this.model.selected ? $r('app.color.selected_bg') : Color.Transparent)
    .onClick(() => this.model.activate(row))
    .bindContextMenu(this.rowMenu(row), ResponseType.RightClick)
    .bindContextMenu(this.rowMenu(row), ResponseType.LongPress)
  }

  build() {
    Column() {
      SectionHeader({ title: $r('app.string.explorer_title'), subtitle: this.projectName }) {
        this.headerActions()
      }
      if (this.model.rows.length === 0) {
        Column() {
          EmptyState({ title: $r('app.string.explorer_empty_title'), message: $r('app.string.explorer_empty_message') }) {
            ActionButton({ text: $r('app.string.explorer_new_file'), kind: ActionStyle.PRIMARY,
              onTap: () => this.model.newFile() })
          }
        }
        .width(UiConst.FULL)
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      } else {
        List() {
          ForEach(this.model.rows, (row: TreeRow) => {
            ListItem() {
              this.treeRow(row)
            }
          }, (row: TreeRow) => row.path + '|' + row.expanded + '|' + row.git + '|' + row.depth)
        }
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        .scrollBar(BarState.Auto)
      }
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .backgroundColor($r('app.color.sidebar_bg'))
  }
}
