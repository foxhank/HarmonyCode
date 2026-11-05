import { Strings } from '../../core/common/Strings';
import { TimeFormat } from '../../core/common/TimeFormat';
import { CommandId } from '../commands/CommandService';
import { UiConst } from '../../components/UiConst';
import { CatalogText } from '../app/CatalogText';
import { Languages } from '../editor/Languages';
import { ScmOp } from '../scm/ScmModel';
import { OverlayId } from './WorkbenchState';
import { Workspace } from './Workspace';

/** Bottom status line: environment, branch, sync state, cursor, language. */
@ComponentV2
export struct StatusBar {
  @Param @Require ws: Workspace;

  @Builder
  item(text: string, onTap?: () => void) {
    Text(text)
      .fontSize($r('app.float.font_xs'))
      .fontColor($r('app.color.statusbar_text'))
      .maxLines(UiConst.MAX_LINES_TITLE)
      .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s') })
      .height(UiConst.FULL)
      .onClick(() => {
        if (onTap !== undefined) {
          onTap();
        }
      })
  }

  private busyText(): string {
    const op = this.ws.scm.busy;
    if (op === ScmOp.NONE) {
      return '';
    }
    const p = this.ws.scm.progress;
    return Strings.get('status_busy_' + op) + (p.length > 0 ? ' ' + p : '');
  }

  build() {
    Row() {
      Text(this.ws.target !== null ? Strings.get('status_runs_on', this.ws.target.displayName()) :
        CatalogText.envName(this.ws.project.envId))
        .fontSize($r('app.float.font_xs'))
        .fontColor($r('app.color.text_on_accent'))
        .backgroundColor($r('app.color.statusbar_remote_bg'))
        .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_s') })
        .height(UiConst.FULL)
        .onClick(() => this.ws.commands.run(CommandId.ENVIRONMENT))
      if (this.ws.target !== null) {
        this.item(this.ws.target.syncing ? Strings.get('status_syncing') :
          (this.ws.target.error.length > 0 ? Strings.get('status_sync_error') :
            (this.ws.target.lastSync > 0 ? Strings.get('status_synced', TimeFormat.relative(this.ws.target.lastSync)) :
              Strings.get('status_not_synced'))), () => this.ws.commands.run(CommandId.SYNC))
      }
      if (this.ws.scm.branch.length > 0) {
        this.item(Strings.get('status_branch', this.ws.scm.branch, this.ws.scm.changeCount),
          () => this.ws.ui.openOverlay(OverlayId.BRANCHES))
      }
      this.item(this.busyText())
      Blank()
      if (this.ws.editor.active !== undefined) {
        this.item(Strings.get('status_ln_col', this.ws.editor.line, this.ws.editor.col))
        this.item(Strings.get('status_spaces', this.ws.deps.settings.tabSize))
        this.item(Strings.get('status_encoding'))
        this.item(Languages.nameFor(this.ws.editor.active?.path ?? ''))
      }
      this.item(this.ws.terminal.label)
    }
    .width(UiConst.FULL)
    .height($r('app.float.statusbar_height'))
    .backgroundColor($r('app.color.statusbar_bg'))
    .border({ width: { top: $r('app.float.border_width') }, color: $r('app.color.border') })
  }
}
