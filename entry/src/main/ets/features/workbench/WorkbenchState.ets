import { AppConfig } from '../../core/common/AppConfig';
import { LayoutState } from '../app/LayoutState';

/** Width of the agent panel on tablets and desktops (vp). */
class AgentPanelSize {
  static readonly DEFAULT: number = 400;
  static readonly MIN: number = 300;
  static readonly MAX: number = 720;
}

/** Views that can fill the side bar (desktop/tablet) or the screen (phone). */
export class ViewId {
  static readonly EXPLORER: string = 'explorer';
  static readonly SEARCH: string = 'search';
  static readonly SCM: string = 'scm';
  static readonly EDITOR: string = 'editor';
  static readonly TERMINAL: string = 'terminal';
  /** Phone only: the agent fills the screen. */
  static readonly AGENT: string = 'agent';
}

/** Settings pages that can be opened directly (see features/settings/SettingsCategories). */
export class SettingsCategory {
  static readonly NONE: string = '';
  static readonly AGENT: string = 'agent';
}

/** Floating layers above the workbench. */
export class OverlayId {
  static readonly NONE: string = '';
  static readonly QUICK_OPEN: string = 'quickOpen';
  static readonly SETTINGS: string = 'settings';
  static readonly BRANCHES: string = 'branches';
  /** Where the project runs (device or computer) and its languages and tools. */
  static readonly ENVIRONMENT: string = 'environment';
}

/** Which parts of the workbench are visible, and their sizes. No file or Git logic here. */
@ObservedV2
export class WorkbenchState {
  @Trace sideView: string = ViewId.EXPLORER;
  @Trace sidebarVisible: boolean = true;
  @Trace panelVisible: boolean = true;
  @Trace panelMaximized: boolean = false;
  @Trace sidebarWidth: number = AppConfig.SIDEBAR_DEFAULT;
  @Trace panelHeight: number = AppConfig.PANEL_DEFAULT;
  /** Phone only: which single view fills the screen. */
  @Trace phoneView: string = ViewId.EXPLORER;
  @Trace overlay: string = OverlayId.NONE;
  /** Desktop/tablet: the agent panel on the right. */
  @Trace agentVisible: boolean = false;
  @Trace agentWidth: number = AgentPanelSize.DEFAULT;
  /** Category the settings overlay opens at ('' = the category list). */
  @Trace settingsCategory: string = SettingsCategory.NONE;
  private layout: LayoutState;

  constructor(layout: LayoutState) {
    this.layout = layout;
    // Tablets start with the editor visible; the side bar slides in on demand.
    this.sidebarVisible = !layout.isTablet;
  }

  /** Shows a side view (explorer/search/scm). Clicking the active one again hides the side bar. */
  showSideView(id: string): void {
    if (this.layout.isPhone) {
      this.phoneView = id;
      return;
    }
    if (this.sidebarVisible && this.sideView === id) {
      this.sidebarVisible = false;
      return;
    }
    this.sideView = id;
    this.sidebarVisible = true;
  }

  /** Brings the editor forward (after opening a file). */
  showEditor(): void {
    if (this.layout.isPhone) {
      this.phoneView = ViewId.EDITOR;
    } else if (this.layout.isTablet) {
      this.sidebarVisible = false;
    }
  }

  toggleSidebar(): void {
    if (this.layout.isPhone) {
      this.phoneView = ViewId.EXPLORER;
    } else {
      this.sidebarVisible = !this.sidebarVisible;
    }
  }

  toggleTerminal(): void {
    if (this.layout.isPhone) {
      this.phoneView = this.phoneView === ViewId.TERMINAL ? ViewId.EDITOR : ViewId.TERMINAL;
    } else {
      this.panelVisible = !this.panelVisible;
    }
  }

  showTerminal(): void {
    if (this.layout.isPhone) {
      this.phoneView = ViewId.TERMINAL;
    } else {
      this.panelVisible = true;
    }
  }

  toggleMaximizePanel(): void {
    this.panelMaximized = !this.panelMaximized;
  }

  resizeSidebar(width: number): void {
    this.sidebarWidth = Math.max(AppConfig.SIDEBAR_MIN, Math.min(AppConfig.SIDEBAR_MAX, width));
  }

  resizePanel(height: number, available: number): void {
    const max = available * AppConfig.PANEL_MAX_RATIO;
    this.panelHeight = Math.max(AppConfig.PANEL_MIN, Math.min(max, height));
  }

  openOverlay(id: string): void {
    if (id === OverlayId.SETTINGS) {
      this.settingsCategory = SettingsCategory.NONE;
    }
    this.overlay = id;
  }

  /** Opens the settings overlay at a category. */
  openSettings(category: string): void {
    this.settingsCategory = category;
    this.overlay = OverlayId.SETTINGS;
  }

  /** Shows the agent (phone: full screen; wider: the right-hand panel). */
  showAgent(): void {
    if (this.layout.isPhone) {
      this.phoneView = ViewId.AGENT;
    } else {
      this.agentVisible = true;
    }
  }

  toggleAgent(): void {
    if (this.layout.isPhone) {
      this.phoneView = this.phoneView === ViewId.AGENT ? ViewId.EDITOR : ViewId.AGENT;
    } else {
      this.agentVisible = !this.agentVisible;
    }
  }

  resizeAgent(width: number): void {
    this.agentWidth = Math.max(AgentPanelSize.MIN, Math.min(AgentPanelSize.MAX, width));
  }

  closeOverlay(): void {
    this.overlay = OverlayId.NONE;
  }
}
