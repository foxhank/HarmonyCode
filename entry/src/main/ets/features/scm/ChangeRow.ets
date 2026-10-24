import { PathUtil } from '../../core/fs/PathUtil';
import { ChangeCode, GitChange } from '../../core/git/GitTypes';
import { IconButton } from '../../components/IconButton';
import { UiConst } from '../../components/UiConst';
import { layoutState } from '../app/LayoutState';
import { gitColor } from './GitColors';

/** One changed file: name, folder, status letter, and stage/unstage/discard actions. */
@ComponentV2
export struct ChangeRow {
  @Param @Require change: GitChange;
  @Event onOpen: () => void = () => {
  };
  @Event onStage: () => void = () => {
  };
  @Event onUnstage: () => void = () => {
  };
  @Event onDiscard: () => void = () => {
  };

  build() {
    Row({ space: $r('app.float.space_xs') }) {
      Image($r('app.media.ic_file'))
        .width($r('app.float.icon_size_small'))
        .height($r('app.float.icon_size_small'))
        .fillColor($r('app.color.file_icon'))
      Text(PathUtil.baseName(this.change.path))
        .fontSize($r('app.float.font_m'))
        .fontColor(gitColor(this.change.code))
        .maxLines(UiConst.MAX_LINES_TITLE)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .decoration({ type: this.change.code === ChangeCode.DELETED ? TextDecorationType.LineThrough : TextDecorationType.None })
      Text(this.change.path.indexOf('/') >= 0 ? PathUtil.dirName(this.change.path) : '')
        .fontSize($r('app.float.font_xs'))
        .fontColor($r('app.color.text_muted'))
        .maxLines(UiConst.MAX_LINES_TITLE)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      if (!this.change.staged) {
        IconButton({ icon: $r('app.media.ic_undo'), label: $r('app.string.scm_discard'),
          onTap: () => this.onDiscard() })
        IconButton({ icon: $r('app.media.ic_add'), label: $r('app.string.scm_stage'),
          onTap: () => this.onStage() })
      } else {
        IconButton({ icon: $r('app.media.ic_remove'), label: $r('app.string.scm_unstage'),
          onTap: () => this.onUnstage() })
      }
      Text(this.change.code)
        .fontSize($r('app.float.font_s'))
        .fontWeight(FontWeight.Medium)
        .fontColor(gitColor(this.change.code))
        .width($r('app.float.status_letter_width'))
        .textAlign(TextAlign.Center)
    }
    .width(UiConst.FULL)
    .height(layoutState.isDesktop ? $r('app.float.tree_row_height') : $r('app.float.list_row_touch'))
    .padding({ left: $r('app.float.space_l'), right: $r('app.float.space_xs') })
    .onClick(() => this.onOpen())
  }
}
