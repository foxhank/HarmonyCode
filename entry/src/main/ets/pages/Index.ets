import { UiConst } from '../components/UiConst';
import { appNav, Routes } from '../features/app/AppNavigation';
import { DialogHost } from '../features/dialogs/DialogHost';
import { dialogs } from '../features/dialogs/DialogModel';
import { ToastHost } from '../features/dialogs/ToastHost';
import { toasts } from '../features/dialogs/ToastModel';
import { SettingsPage } from '../features/settings/SettingsPage';
import { ClonePage } from '../features/welcome/ClonePage';
import { NewProjectPage } from '../features/welcome/NewProjectPage';
import { WelcomePage } from '../features/welcome/WelcomePage';
import { WorkbenchPage } from '../features/workbench/WorkbenchPage';

/** App root: Welcome -> New Project / Clone / Settings -> Workbench, with app-wide dialogs on top. */
@Entry
@ComponentV2
struct Index {
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
