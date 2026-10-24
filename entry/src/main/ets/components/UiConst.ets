/** Unitless UI numbers (opacities, ratios, durations). Sizes and colors live in resources. */
export class UiConst {
  static readonly DISABLED_OPACITY: number = 0.4;
  static readonly MUTED_OPACITY: number = 0.7;
  static readonly ANIM_FAST_MS: number = 150;
  static readonly ANIM_NORMAL_MS: number = 220;
  static readonly MAX_LINES_TITLE: number = 1;
  static readonly MAX_LINES_BODY: number = 3;
  static readonly LAYOUT_WEIGHT_FILL: number = 1;
  static readonly FULL: string = '100%';
  /** Max width of dialogs and toasts relative to the window. */
  static readonly FLOATING_MAX_WIDTH: string = '90%';
  /** Share of the window height a sheet / quick-open list may use. */
  static readonly POPUP_MAX_HEIGHT_RATIO: number = 0.6;
  /** Share of the window width the tablet sidebar overlay may use. */
  static readonly OVERLAY_SIDEBAR_RATIO: number = 0.8;
  /** Height of the settings overlay on tablet/desktop, relative to the window. */
  static readonly SETTINGS_OVERLAY_HEIGHT: string = '80%';
  /** File-tree indentation per level (vp); a number because it's multiplied by depth. */
  static readonly TREE_INDENT: number = 12;
  static readonly Z_OVERLAY: number = 10;
  static readonly Z_DIALOG: number = 20;
  static readonly Z_TOAST: number = 30;
}
