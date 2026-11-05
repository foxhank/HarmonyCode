import { appNav } from '../app/AppNavigation';
import { AppRestart } from '../app/AppRestart';
import { toasts } from '../dialogs/ToastModel';
import { CommandId, WorkbenchCommand } from '../commands/CommandService';
import { OverlayId, ViewId } from './WorkbenchState';
import { Workspace } from './Workspace';

/** Registers every workbench command (palette entries + shortcut targets). */
export function registerWorkbenchCommands(ws: Workspace): void {
  const cmds: WorkbenchCommand[] = [
    {
      id: CommandId.QUICK_OPEN, titleKey: 'cmd_quick_open', keys: 'Ctrl+P', run: () => {
        ws.quickOpen.showFiles();
        ws.ui.openOverlay(OverlayId.QUICK_OPEN);
      }
    },
    {
      id: CommandId.PALETTE, titleKey: 'cmd_palette', keys: 'Ctrl+Shift+P', run: () => {
        ws.quickOpen.showCommands();
        ws.ui.openOverlay(OverlayId.QUICK_OPEN);
      }
    },
    { id: CommandId.SAVE, titleKey: 'cmd_save', keys: 'Ctrl+S', run: () => ws.editor.saveActive() },
    { id: CommandId.SAVE_ALL, titleKey: 'cmd_save_all', keys: 'Ctrl+Alt+S', run: () => ws.editor.saveAll() },
    { id: CommandId.CLOSE_TAB, titleKey: 'cmd_close_tab', keys: 'Ctrl+W', run: () => ws.editor.closeActive() },
    { id: CommandId.NEXT_TAB, titleKey: 'cmd_next_tab', keys: 'Ctrl+Tab', run: () => ws.editor.activateRelative(1) },
    {
      id: CommandId.PREV_TAB, titleKey: 'cmd_prev_tab', keys: 'Ctrl+Shift+Tab',
      run: () => ws.editor.activateRelative(-1)
    },
    { id: CommandId.TOGGLE_SIDEBAR, titleKey: 'cmd_toggle_sidebar', keys: 'Ctrl+B', run: () => ws.ui.toggleSidebar() },
    {
      id: CommandId.TOGGLE_TERMINAL, titleKey: 'cmd_toggle_terminal', keys: 'Ctrl+`',
      run: () => ws.ui.toggleTerminal()
    },
    { id: CommandId.TOGGLE_AGENT, titleKey: 'cmd_toggle_agent', keys: 'Ctrl+Shift+A', run: () => ws.ui.toggleAgent() },
    {
      id: CommandId.EXPLORER, titleKey: 'cmd_show_explorer', keys: 'Ctrl+Shift+E',
      run: () => ws.ui.showSideView(ViewId.EXPLORER)
    },
    {
      id: CommandId.SEARCH, titleKey: 'cmd_show_search', keys: 'Ctrl+Shift+F',
      run: () => ws.ui.showSideView(ViewId.SEARCH)
    },
    { id: CommandId.GIT, titleKey: 'cmd_show_scm', keys: 'Ctrl+Shift+G', run: () => ws.ui.showSideView(ViewId.SCM) },
    {
      id: CommandId.RUN, titleKey: 'cmd_run', keys: 'F5', run: () => {
        ws.ui.showTerminal();
        ws.editor.saveAll();
        ws.terminal.run();
      }
    },
    { id: CommandId.NEW_FILE, titleKey: 'cmd_new_file', keys: '', run: () => ws.explorer.newFile() },
    { id: CommandId.NEW_FOLDER, titleKey: 'cmd_new_folder', keys: '', run: () => ws.explorer.newFolder() },
    {
      id: CommandId.GIT_COMMIT, titleKey: 'cmd_git_commit', keys: '', run: () => ws.ui.showSideView(ViewId.SCM)
    },
    { id: CommandId.GIT_PULL, titleKey: 'cmd_git_pull', keys: '', run: () => ws.scm.pull() },
    { id: CommandId.GIT_PUSH, titleKey: 'cmd_git_push', keys: '', run: () => ws.scm.push() },
    {
      id: CommandId.GIT_BRANCH, titleKey: 'cmd_git_branch', keys: '',
      run: () => ws.ui.openOverlay(OverlayId.BRANCHES)
    },
    {
      id: CommandId.ENVIRONMENT, titleKey: 'cmd_environment', keys: '', run: () => {
        ws.tools?.refresh();
        ws.ui.openOverlay(OverlayId.ENVIRONMENT);
      }
    },
    {
      id: CommandId.SYNC, titleKey: 'cmd_sync_remote', keys: 'Ctrl+Shift+Y', run: () => {
        if (ws.target !== null) {
          ws.editor.saveAll();
          ws.target.syncNow();
        } else {
          ws.ui.openOverlay(OverlayId.ENVIRONMENT);
        }
      }
    },
    {
      id: CommandId.SETTINGS, titleKey: 'cmd_settings', keys: 'Ctrl+,',
      run: () => ws.ui.openOverlay(OverlayId.SETTINGS)
    },
    {
      id: CommandId.CLOSE_PROJECT, titleKey: 'cmd_close_project', keys: '', run: () => {
        ws.editor.closeAll().then((ok: boolean) => {
          if (ok) {
            appNav.pop();
          }
        });
      }
    },
    {
      // Switching Linux environments needs a fresh process (QEMU boots once per process).
      id: CommandId.RESTART_APP, titleKey: 'cmd_restart_app', keys: '', run: () => {
        ws.editor.closeAll().then((ok: boolean) => {
          if (ok) {
            const error = AppRestart.restart(ws.project.id);
            if (error.length > 0) {
              toasts.error(error);
            }
          }
        });
      }
    },
  ];
  ws.commands.register(cmds);
}
