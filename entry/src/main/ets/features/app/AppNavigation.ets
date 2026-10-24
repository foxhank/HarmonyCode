/** Route names for the app's Navigation stack. */
export class Routes {
  static readonly NEW_PROJECT: string = 'newProject';
  static readonly CLONE: string = 'clone';
  static readonly WORKBENCH: string = 'workbench';
  static readonly SETTINGS: string = 'settings';
}

/** The single navigation stack (welcome screen is the root). */
export const appNav: NavPathStack = new NavPathStack();

/** Opens a project, replacing any open workbench so Back returns to the welcome screen. */
export function openWorkbench(projectId: string): void {
  appNav.clear(false);
  appNav.pushPathByName(Routes.WORKBENCH, projectId, false);
}
