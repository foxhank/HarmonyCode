import { Strings } from '../../core/common/Strings';
import { projectRepository } from '../../core/project/ProjectRepository';
import { settingsStore } from '../../core/settings/SettingsStore';
import { UiConst } from '../../components/UiConst';
import { appNav } from '../app/AppNavigation';
import { AppServices } from '../app/AppServices';
import { layoutState } from '../app/LayoutState';
import { CommandId } from '../commands/CommandService';
import { chordOf } from '../commands/KeyChord';
import { dialogs } from '../dialogs/DialogModel';
import { toasts } from '../dialogs/ToastModel';
import { OverlayLayer } from './OverlayLayer';
import { PhoneLayout } from './PhoneLayout';
import { StatusBar } from './StatusBar';
import { TitleBar } from './TitleBar';
import { WideLayout } from './WideLayout';
import { OverlayId } from './WorkbenchState';
import { Workspace } from './Workspace';

const ESC_CHORD: string = 'Esc';

/**
 * The IDE window for one project. Builds the Workspace from the route parameter, picks a
 * layout for the current breakpoint, and routes keyboard shortcuts to commands.
 */
@ComponentV2
export struct WorkbenchPage {
  @Local ws: Workspace | undefined = undefined;

  private open(projectId: string): void {
    const project = projectRepository.get(projectId);
    if (project === undefined) {
      toasts.error(Strings.get('workbench_project_missing'));
      appNav.pop();
      return;
    }
    this.ws = new Workspace(project, {
      layout: layoutState,
      git: AppServices.git,
      settings: settingsStore,
      dialogs: dialogs,
      toasts: toasts
    });
  }

  aboutToDisappear(): void {
    if (this.ws !== undefined) {
      this.ws.dispose();
      this.ws = undefined;
    }
  }

  private close(): void {
    if (this.ws === undefined) {
      appNav.pop();
    } else {
      this.ws.commands.run(CommandId.CLOSE_PROJECT);
    }
  }

  private onKey(e: KeyEvent): void {
    const ws = this.ws;
    const chord = chordOf(e);
    if (ws === undefined || chord.length === 0) {
      return;
    }
    if (chord === ESC_CHORD && ws.ui.overlay !== OverlayId.NONE) {
      ws.ui.closeOverlay();
      return;
    }
    const id = ws.commands.idForKeys(chord);
    if (id.length > 0) {
      ws.commands.runShortcut(id);
    }
  }

  @Builder
  body(ws: Workspace) {
    Stack() {
      Column() {
        TitleBar({ ws: ws, onBack: () => this.close() })
        Column() {
          if (layoutState.isPhone) {
            PhoneLayout({ ws: ws })
          } else {
            WideLayout({ ws: ws })
          }
        }
        .width(UiConst.FULL)
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        if (!layoutState.isPhone) {
          StatusBar({ ws: ws })
        }
      }
      .width(UiConst.FULL)
      .height(UiConst.FULL)

      OverlayLayer({ ws: ws })
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .onKeyEvent((e: KeyEvent) => this.onKey(e))
  }

  build() {
    NavDestination() {
      if (this.ws !== undefined) {
        this.body(this.ws)
      }
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.app_bg'))
    .onReady((ctx: NavDestinationContext) => {
      const id = ctx.pathInfo.param as string;
      this.open(id);
    })
    .onBackPressed(() => {
      const ws = this.ws;
      if (ws !== undefined && ws.ui.overlay !== OverlayId.NONE) {
        ws.ui.closeOverlay();
      } else {
        this.close();
      }
      return true;
    })
  }
}
