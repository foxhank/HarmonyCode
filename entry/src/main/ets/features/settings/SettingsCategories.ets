/** A top-level settings page. */
export interface CategoryDef {
  id: string;
  icon: Resource;
  title: Resource;
  summary: Resource;
}

/** Settings categories, in display order. Ids are stable (used to open a page directly). */
export class SettingsCategories {
  static readonly APPEARANCE: string = 'appearance';
  static readonly COMPILER: string = 'compiler';
  static readonly EDITOR: string = 'editor';
  static readonly TERMINAL: string = 'terminal';
  static readonly GIT: string = 'git';
  static readonly AGENT: string = 'agent';
  static readonly ABOUT: string = 'about';

  static all(): CategoryDef[] {
    return [
      {
        id: SettingsCategories.APPEARANCE, icon: $r('app.media.ic_palette'),
        title: $r('app.string.settings_section_appearance'), summary: $r('app.string.settings_summary_appearance')
      },
      {
        id: SettingsCategories.COMPILER, icon: $r('app.media.ic_play'),
        title: $r('app.string.settings_section_compiler'), summary: $r('app.string.settings_summary_compiler')
      },
      {
        id: SettingsCategories.EDITOR, icon: $r('app.media.ic_code'),
        title: $r('app.string.settings_section_editor'), summary: $r('app.string.settings_summary_editor')
      },
      {
        id: SettingsCategories.TERMINAL, icon: $r('app.media.ic_terminal'),
        title: $r('app.string.settings_section_terminal'), summary: $r('app.string.settings_summary_terminal')
      },
      {
        id: SettingsCategories.GIT, icon: $r('app.media.ic_git_branch'),
        title: $r('app.string.settings_section_git'), summary: $r('app.string.settings_summary_git')
      },
      {
        id: SettingsCategories.AGENT, icon: $r('app.media.ic_agent'),
        title: $r('app.string.settings_section_agent'), summary: $r('app.string.settings_summary_agent')
      },
      {
        id: SettingsCategories.ABOUT, icon: $r('app.media.ic_info'),
        title: $r('app.string.settings_section_about'), summary: $r('app.string.settings_summary_about')
      }
    ];
  }

  static get(id: string): CategoryDef | undefined {
    return SettingsCategories.all().find((c: CategoryDef) => c.id === id);
  }
}
