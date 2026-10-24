import { UiConst } from '../../components/UiConst';
import { ExplorerView } from '../explorer/ExplorerView';
import { ScmView } from '../scm/ScmView';
import { SearchView } from '../search/SearchView';
import { OverlayId, ViewId } from './WorkbenchState';
import { Workspace } from './Workspace';

/** Shows one side view (explorer, search or source control). Shared by every layout. */
@ComponentV2
export struct SideBar {
  @Param @Require ws: Workspace;
  @Param @Require view: string;

  build() {
    Column() {
      if (this.view === ViewId.SEARCH) {
        SearchView({ model: this.ws.search })
      } else if (this.view === ViewId.SCM) {
        ScmView({ model: this.ws.scm, onPickBranch: () => this.ws.ui.openOverlay(OverlayId.BRANCHES) })
      } else {
        ExplorerView({ model: this.ws.explorer, projectName: this.ws.project.name })
      }
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .backgroundColor($r('app.color.sidebar_bg'))
  }
}
