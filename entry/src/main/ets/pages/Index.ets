import { UiConst } from '../components/UiConst';
import { projectRepository } from '../core/project/ProjectRepository';
import { appNav, openWorkbench, Routes } from '../features/app/AppNavigation';
import { AppRestart } from '../features/app/AppRestart';
import { DialogHost } from '../features/dialogs/DialogHost';
import { dialogs } from '../features/dialogs/DialogModel';
import { ToastHost } from '../features/dialogs/ToastHost';
import { toasts } from '../features/dialogs/ToastModel';
import { SettingsPage } from '../features/settings/SettingsPage';
import { ClonePage } from '../features/welcome/ClonePage';
import { HostEditorPage } from '../features/remote/HostEditorPage';
import { RemotePage } from '../features/remote/RemotePage';
import { NewProjectPage } from '../features/welcome/NewProjectPage';
import { WelcomePage } from '../features/welcome/WelcomePage';
import { WorkbenchPage } from '../features/workbench/WorkbenchPage';

/** App root: Welcome -> New Project / Clone / Settings / Remote -> Workbench, with app-wide dialogs on top. */
@Entry
@ComponentV2
struct Index {
  aboutToAppear(): void {
    // After a restart (e.g. to switch Linux environments) go straight back to the project.
    const id = AppRestart.takePendingProject();
    if (id.length > 0 && projectRepository.get(id) !== undefined) {
      openWorkbench(id);
    }
  }

  @Builder
  routes(name: string) {
    if (name === Routes.NEW_PROJECT) {
      NewProjectPage()
    } else if (name === Routes.CLONE) {
      ClonePage()
    } else if (name === Routes.SETTINGS) {
      SettingsPage()
    } else if (name === Routes.WORKBENCH) {
      WorkbenchPage()
    } else if (name === Routes.REMOTE) {
      RemotePage()
    } else if (name === Routes.HOST_EDITOR) {
      HostEditorPage()
    }
  }

  build() {
    Stack() {
      Navigation(appNav) {
        WelcomePage()
      }
      .mode(NavigationMode.Stack)
      .hideTitleBar(true)
      .hideToolBar(true)
      .navDestination(this.routes)
      .backgroundColor($r('app.color.app_bg'))

      DialogHost({ model: dialogs })
      ToastHost({ model: toasts })
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .backgroundColor($r('app.color.app_bg'))
  }
}
