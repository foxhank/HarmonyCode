import { EditorTheme } from '../editor/EditorModel';
import { TerminalTheme } from '../terminal/TerminalController';
import { appearance } from './Appearance';
import { ColorUtil } from './ColorUtil';

/** Theme values for the web views, read from color resources (light or dark set). */
export class WebTheme {
  static editor(): EditorTheme {
    return { dark: appearance.isDark, background: ColorUtil.css($r('app.color.editor_bg')) };
  }

  static terminal(): TerminalTheme {
    return {
      dark: appearance.isDark,
      background: ColorUtil.css($r('app.color.terminal_bg')),
      foreground: ColorUtil.css($r('app.color.terminal_fg')),
      cursor: ColorUtil.css($r('app.color.terminal_cursor')),
      selection: ColorUtil.css($r('app.color.terminal_selection'))
    };
  }
}
