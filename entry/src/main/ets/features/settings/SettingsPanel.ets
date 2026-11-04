import { agentSettings } from '../../core/settings/AgentSettingsStore';
import { IconButton } from '../../components/IconButton';
import { UiConst } from '../../components/UiConst';
import { layoutState } from '../app/LayoutState';
import { AgentSettings } from './pages/AgentSettings';
import {
  AboutSettings, AppearanceSettings, CompilerSettings, EditorSettings, GitSettings, TerminalSettings
} from './pages/GeneralPages';
import { ProviderSettings } from './pages/ProviderSettings';
import { CategoryDef, SettingsCategories } from './SettingsCategories';
import { NavRow } from './SettingsWidgets';

/** Panel width from which the category list and the page are shown side by side (vp). */
const SPLIT_MIN_WIDTH: number = 600;

/**
 * All settings, in levels: categories (Appearance, Compiler, Editor, Terminal, Git, Agent, About)
 * → a category's page → sub-pages (an agent provider). Wide panels show the category list beside
 * the page; narrow ones show one level at a time with a back button. Used as a page (from Welcome)
 * and as an overlay (from the workbench).
 */
@ComponentV2
export struct SettingsPanel {
  /** Category to open at first ('' = the list on narrow screens, the first category on wide ones). */
  @Param initialCategory: string = '';
  @Local category: string = '';
  /** Agent › provider sub-page ('' = none). */
  @Local providerId: string = '';
  @Local panelWidth: number = 0;

  aboutToAppear(): void {
    agentSettings.ensureLoaded(getContext(this));
    this.category = this.initialCategory;
  }

  private get split(): boolean {
    return this.panelWidth >= SPLIT_MIN_WIDTH;
  }

  private get touch(): boolean {
    return !layoutState.isDesktop;
  }

  /** The category shown on the right in split mode. */
  private get shownCategory(): string {
    if (this.category.length > 0) {
      return this.category;
    }
    return this.split ? SettingsCategories.APPEARANCE : '';
  }

  private open(id: string): void {
    this.category = id;
    this.providerId = '';
  }

  private back(): void {
    if (this.providerId.length > 0) {
      this.providerId = '';
    } else {
      this.category = '';
    }
  }

  private pageTitle(): ResourceStr {
    if (this.providerId.length > 0) {
      const p = agentSettings.provider(this.providerId);
      return p !== undefined ? p.name : '';
    }
    const c = SettingsCategories.get(this.shownCategory);
    return c !== undefined ? c.title : '';
  }

  @Builder
  categoryList() {
    List({ space: UiConst.LIST_GAP_TIGHT }) {
      ForEach(SettingsCategories.all(), (c: CategoryDef) => {
        ListItem() {
          NavRow({
            icon: c.icon, title: c.title, subtitle: this.split ? '' : c.summary, touch: this.touch,
            selected: this.split && this.shownCategory === c.id, onTap: () => this.open(c.id)
          })
        }
      }, (c: CategoryDef) => c.id)
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .padding($r('app.float.space_s'))
    .scrollBar(BarState.Auto)
  }

  @Builder
  pageBody() {
    if (this.providerId.length > 0) {
      ProviderSettings({ providerId: this.providerId, onDeleted: () => this.back() })
    } else if (this.shownCategory === SettingsCategories.APPEARANCE) {
      AppearanceSettings()
    } else if (this.shownCategory === SettingsCategories.COMPILER) {
      CompilerSettings()
    } else if (this.shownCategory === SettingsCategories.EDITOR) {
      EditorSettings()
    } else if (this.shownCategory === SettingsCategories.TERMINAL) {
      TerminalSettings()
    } else if (this.shownCategory === SettingsCategories.GIT) {
      GitSettings()
    } else if (this.shownCategory === SettingsCategories.AGENT) {
      AgentSettings({ touch: this.touch, onOpenProvider: (id: string) => {
        this.providerId = id;
      } })
    } else {
      AboutSettings()
    }
  }

  @Builder
  page() {
    Column() {
      Row({ space: $r('app.float.space_xs') }) {
        if (!this.split || this.providerId.length > 0) {
          IconButton({
            icon: $r('app.media.ic_arrow_back'), label: $r('app.string.action_back'),
            buttonSize: this.touch ? $r('app.float.icon_button_size_touch') : $r('app.float.icon_button_size'),
            onTap: () => this.back()
          })
        }
        if (this.providerId.length > 0) {
          Text($r('app.string.settings_section_agent'))
            .fontSize($r('app.float.font_l'))
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => this.back())
          Text('›')
            .fontSize($r('app.float.font_l'))
            .fontColor($r('app.color.text_muted'))
        }
        Text(this.pageTitle())
          .fontSize($r('app.float.font_l'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      }
      .width(UiConst.FULL)
      .height($r('app.float.section_header_height_large'))
      .padding({ left: $r('app.float.space_s'), right: $r('app.float.space_l') })

      Scroll() {
        Column() {
          this.pageBody()
        }
        .width(UiConst.FULL)
        .padding({ left: $r('app.float.space_xl'), right: $r('app.float.space_xl'), bottom: $r('app.float.space_xl'),
          top: $r('app.float.space_s') })
        .constraintSize({ maxWidth: $r('app.float.form_max_width') })
      }
      .width(UiConst.FULL)
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
  }

  build() {
    Row() {
      if (this.split) {
        Column() {
          this.categoryList()
        }
        .width($r('app.float.settings_nav_width'))
        .height(UiConst.FULL)
        .border({ width: { right: $r('app.float.border_width') }, color: $r('app.color.border') })
        Column() {
          this.page()
        }
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        .height(UiConst.FULL)
      } else if (this.shownCategory.length === 0) {
        this.categoryList()
      } else {
        this.page()
      }
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .onAreaChange((_old: Area, next: Area) => {
      this.panelWidth = Number(next.width);
    })
  }
}
