import { Splitter } from '../../components/Splitter';
import { UiConst } from '../../components/UiConst';
import { CommandId } from '../commands/CommandService';
import { EditorPane } from '../editor/EditorPane';
import { TerminalPanel } from '../terminal/TerminalPanel';
import { Workspace } from './Workspace';

/** Editor on top, terminal panel below with a drag handle between them (tablet and desktop). */
@ComponentV2
export struct EditorArea {
  @Param @Require ws: Workspace;
  @Local areaHeight: number = 0;
  private dragBase: number = 0;

  private editorVisible(): boolean {
    return !(this.ws.ui.panelVisible && this.ws.ui.panelMaximized);
  }

  build() {
    Column() {
      EditorPane({ model: this.ws.editor, onCommand: (id: string) => this.ws.commands.run(id) })
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        .visibility(this.editorVisible() ? Visibility.Visible : Visibility.None)

      if (this.ws.ui.panelVisible) {
        if (!this.ws.ui.panelMaximized) {
          Splitter({
            vertical: false,
            onStart: () => {
              this.dragBase = this.ws.ui.panelHeight;
            },
            onMove: (offset: number) => this.ws.ui.resizePanel(this.dragBase - offset, this.areaHeight)
          })
        }
      }
      // Kept alive while hidden so the shell session and scrollback survive.
      TerminalPanel({
        model: this.ws.terminal,
        maximized: this.ws.ui.panelMaximized,
        onRun: () => this.ws.commands.run(CommandId.RUN),
        onToggleMaximize: () => this.ws.ui.toggleMaximizePanel(),
        onClose: () => this.ws.ui.toggleTerminal()
      })
        .height(this.ws.ui.panelMaximized ? undefined : this.ws.ui.panelHeight)
        .layoutWeight(this.ws.ui.panelMaximized ? UiConst.LAYOUT_WEIGHT_FILL : 0)
        .visibility(this.ws.ui.panelVisible ? Visibility.Visible : Visibility.None)
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .onAreaChange((_old: Area, next: Area) => {
      this.areaHeight = Number(next.height);
    })
  }
}
