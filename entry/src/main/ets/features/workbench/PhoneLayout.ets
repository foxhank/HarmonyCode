import { UiConst } from '../../components/UiConst';
import { CommandId } from '../commands/CommandService';
import { EditorPane } from '../editor/EditorPane';
import { TerminalPanel } from '../terminal/TerminalPanel';
import { BottomNav } from './BottomNav';
import { SideBar } from './SideBar';
import { ViewId } from './WorkbenchState';
import { Workspace } from './Workspace';

/** Phone body: one full-screen view at a time, switched from the bottom navigation. */
@ComponentV2
export struct PhoneLayout {
  @Param @Require ws: Workspace;

  private isSideView(view: string): boolean {
    return view === ViewId.EXPLORER || view === ViewId.SEARCH || view === ViewId.SCM;
  }

  private shown(view: string): Visibility {
    return this.ws.ui.phoneView === view ? Visibility.Visible : Visibility.None;
  }

  build() {
    Column() {
      Stack() {
        // Editor and terminal stay alive when hidden so their web views keep their state.
        EditorPane({ model: this.ws.editor, onCommand: (id: string) => this.ws.commands.run(id) })
          .visibility(this.shown(ViewId.EDITOR))
        TerminalPanel({
          model: this.ws.terminal,
          onRun: () => this.ws.commands.run(CommandId.RUN)
        })
          .visibility(this.shown(ViewId.TERMINAL))
        if (this.isSideView(this.ws.ui.phoneView)) {
          SideBar({ ws: this.ws, view: this.ws.ui.phoneView })
        }
      }
      .width(UiConst.FULL)
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)

      BottomNav({ ws: this.ws })
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
  }
}
