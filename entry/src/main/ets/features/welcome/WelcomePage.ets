import { LengthMetrics } from '@kit.ArkUI';
import { PathUtil } from '../../core/fs/PathUtil';
import { ProjectInfo } from '../../core/project/ProjectInfo';
import { projectRepository } from '../../core/project/ProjectRepository';
import { ActionButton, ActionStyle } from '../../components/ActionButton';
import { EmptyState } from '../../components/EmptyState';
import { InputModifier } from '../../components/Modifiers';
import { GlassBarModifier } from '../../components/Surface';
import { UiConst } from '../../components/UiConst';
import { appNav, Routes } from '../app/AppNavigation';
import { layoutState } from '../app/LayoutState';
import { dialogs } from '../dialogs/DialogModel';
import { toasts } from '../dialogs/ToastModel';
import { RemoteHostsView } from '../remote/RemoteHostsView';
import { SettingsPanel } from '../settings/SettingsPanel';
import { CloneView } from './ClonePage';
import { ProjectRow } from './ProjectRow';
import { WelcomeModel } from './WelcomeModel';

/** Sections of the start screen's navigation bar. */
class WelcomeSection {
  static readonly PROJECTS: string = 'projects';
  static readonly REMOTE: string = 'remote';
  static readonly CLONE: string = 'clone';
  static readonly SETTINGS: string = 'settings';
}

interface SectionItem {
  id: string;
  icon: Resource;
  label: Resource;
}

/**
 * Start screen with a navigation bar (a side rail on tablets and desktops, a bottom bar on
 * phones) switching between Projects, Get from VCS and Settings.
 */
@ComponentV2
export struct WelcomePage {
  @Local model: WelcomeModel = new WelcomeModel(projectRepository, dialogs, toasts);
  @Local section: string = WelcomeSection.PROJECTS;
  private inputStyle: InputModifier = new InputModifier();
  private glass: GlassBarModifier = new GlassBarModifier();

  private sections(): SectionItem[] {
    return [
      { id: WelcomeSection.PROJECTS, icon: $r('app.media.ic_folder'), label: $r('app.string.welcome_nav_projects') },
      { id: WelcomeSection.REMOTE, icon: $r('app.media.ic_computer'), label: $r('app.string.welcome_nav_remote') },
      { id: WelcomeSection.CLONE, icon: $r('app.media.ic_git_branch'), label: $r('app.string.welcome_nav_clone') },
      { id: WelcomeSection.SETTINGS, icon: $r('app.media.ic_settings'), label: $r('app.string.settings_title') },
    ];
  }

  build() {
    Column() {
      if (layoutState.isPhone) {
        this.phoneLayout()
      } else {
        this.wideLayout()
      }
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .backgroundColor($r('app.color.app_bg'))
    .bindSheet(this.model.showOpenSheet, this.openSheet(), {
      title: { title: $r('app.string.welcome_open_title') },
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      backgroundColor: $r('app.color.dialog_bg'),
      onDisappear: () => {
        this.model.showOpenSheet = false;
      }
    })
  }

  // ---------- layouts ----------

  @Builder
  wideLayout() {
    Row() {
      Column({ space: $r('app.float.space_xs') }) {
        this.brand(layoutState.isDesktop)
        Column()
          .height($r('app.float.space_l'))
        ForEach(this.sections(), (item: SectionItem) => {
          this.railItem(item)
        }, (item: SectionItem) => item.id)
      }
      .width(layoutState.isDesktop ? $r('app.float.welcome_sidebar_width') : $r('app.float.welcome_rail_width'))
      .height(UiConst.FULL)
      .padding({ left: $r('app.float.space_m'), right: $r('app.float.space_m'), top: $r('app.float.space_xl') })
      .alignItems(layoutState.isDesktop ? HorizontalAlign.Start : HorizontalAlign.Center)
      .backgroundColor($r('app.color.sidebar_bg'))

      Divider().vertical(true).color($r('app.color.border'))

      Column() {
        this.sectionContent(false)
      }
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      .height(UiConst.FULL)
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
  }

  @Builder
  phoneLayout() {
    Column() {
      Column() {
        this.sectionContent(true)
      }
      .width(UiConst.FULL)
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      Row() {
        ForEach(this.sections(), (item: SectionItem) => {
          this.bottomItem(item)
        }, (item: SectionItem) => item.id)
      }
      .attributeModifier(this.glass)
      .width(UiConst.FULL)
      .height($r('app.float.bottomnav_height'))
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
  }

  @Builder
  sectionContent(touch: boolean) {
    if (this.section === WelcomeSection.CLONE) {
      Column() {
        this.sectionHeader($r('app.string.clone_title'), touch)
        CloneView()
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      }
      .width(UiConst.FULL)
      .height(UiConst.FULL)
    } else if (this.section === WelcomeSection.REMOTE) {
      Column() {
        this.sectionHeader($r('app.string.remote_title'), touch)
        RemoteHostsView({ touch: touch })
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      }
      .width(UiConst.FULL)
      .height(UiConst.FULL)
    } else if (this.section === WelcomeSection.SETTINGS) {
      Column() {
        this.sectionHeader($r('app.string.settings_title'), touch)
        SettingsPanel()
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      }
      .width(UiConst.FULL)
      .height(UiConst.FULL)
    } else {
      this.projectsSection(touch)
    }
  }

  @Builder
  sectionHeader(title: ResourceStr, touch: boolean) {
    Text(title)
      .fontSize($r('app.float.font_xl'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
      .width(UiConst.FULL)
      .height($r('app.float.page_header_height'))
      .padding({ left: touch ? $r('app.float.space_l') : $r('app.float.space_xl') })
  }

  @Builder
  projectsSection(touch: boolean) {
    Column({ space: touch ? $r('app.float.space_m') : $r('app.float.space_l') }) {
      if (touch) {
        this.brand(true)
        this.actionButtons(true)
        if (this.model.hasProjects) {
          this.searchField()
        }
      } else {
        Row({ space: $r('app.float.space_s') }) {
          this.searchField()
          this.actionButtons(false)
        }
        .width(UiConst.FULL)
      }
      this.projectList(touch)
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .padding(touch ? $r('app.float.space_l') : $r('app.float.space_xl'))
  }

  @Builder
  railItem(item: SectionItem) {
    Row({ space: $r('app.float.space_m') }) {
      Image(item.icon)
        .width($r('app.float.icon_size'))
        .height($r('app.float.icon_size'))
        .fillColor(this.section === item.id ? $r('app.color.accent') : $r('app.color.icon'))
      if (layoutState.isDesktop) {
        Text(item.label)
          .fontSize($r('app.float.font_m'))
          .fontWeight(this.section === item.id ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.section === item.id ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      }
    }
    .width(layoutState.isDesktop ? UiConst.FULL : $r('app.float.icon_button_size_touch'))
    .height($r('app.float.list_row_touch'))
    .justifyContent(layoutState.isDesktop ? FlexAlign.Start : FlexAlign.Center)
    .padding({
      left: layoutState.isDesktop ? $r('app.float.space_m') : 0,
      right: layoutState.isDesktop ? $r('app.float.space_m') : 0
    })
    .backgroundColor(this.section === item.id ? $r('app.color.accent_soft') : Color.Transparent)
    .borderRadius($r('app.float.radius_l'))
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => {
      this.section = item.id;
    })
    .accessibilityText(item.label)
  }

  @Builder
  bottomItem(item: SectionItem) {
    Column({ space: $r('app.float.space_xxs') }) {
      Image(item.icon)
        .width($r('app.float.icon_size'))
        .height($r('app.float.icon_size'))
        .fillColor(this.section === item.id ? $r('app.color.accent') : $r('app.color.icon'))
      Text(item.label)
        .fontSize($r('app.float.font_xxs'))
        .fontColor(this.section === item.id ? $r('app.color.accent') : $r('app.color.text_secondary'))
    }
    .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
    .height(UiConst.FULL)
    .justifyContent(FlexAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => {
      this.section = item.id;
    })
    .accessibilityText(item.label)
  }

  // ---------- pieces ----------

  @Builder
  brand(withText: boolean) {
    Row({ space: $r('app.float.space_m') }) {
      Stack() {
        Image($r('app.media.ic_logo'))
          .width($r('app.float.icon_size_large'))
          .height($r('app.float.icon_size_large'))
          .fillColor($r('app.color.text_on_bubble'))
      }
      .width($r('app.float.logo_size'))
      .height($r('app.float.logo_size'))
      .borderRadius($r('app.float.radius_l'))
      .linearGradient({ angle: UiConst.GRADIENT_ANGLE,
        colors: [[$r('app.color.bubble_start'), 0], [$r('app.color.bubble_end'), 1]] })
      .shadow({ radius: UiConst.SHADOW_SOFT_RADIUS, color: $r('app.color.bubble_shadow'),
        offsetY: UiConst.SHADOW_SOFT_OFFSET })
      if (withText) {
        Column() {
          Text($r('app.string.app_name'))
            .fontSize($r('app.float.font_xl'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.app_tagline'))
            .fontSize($r('app.float.font_s'))
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
      }
    }
  }

  @Builder
  searchField() {
    TextInput({ text: this.model.filter, placeholder: $r('app.string.welcome_search_placeholder') })
      .attributeModifier(this.inputStyle)
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      .onChange((v: string) => {
        this.model.filter = v;
      })
  }

  @Builder
  actionButtons(stretch: boolean) {
    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.resource($r('app.float.space_s')),
      cross: LengthMetrics.resource($r('app.float.space_s')) } }) {
      ActionButton({
        text: $r('app.string.welcome_new_project'), icon: $r('app.media.ic_add'), kind: ActionStyle.PRIMARY,
        onTap: () => appNav.pushPathByName(Routes.NEW_PROJECT, null)
      })
      ActionButton({
        text: $r('app.string.welcome_open'), icon: $r('app.media.ic_folder_open'), kind: ActionStyle.SECONDARY,
        onTap: () => this.model.showOpen()
      })
      ActionButton({
        text: $r('app.string.welcome_clone'), icon: $r('app.media.ic_git_branch'), kind: ActionStyle.SECONDARY,
        onTap: () => {
          this.section = WelcomeSection.CLONE;
        }
      })
    }
    .width(stretch ? UiConst.FULL : undefined)
  }

  @Builder
  projectList(touch: boolean) {
    if (!this.model.hasProjects) {
      EmptyState({
        icon: $r('app.media.ic_logo'),
        title: $r('app.string.welcome_empty_title'),
        message: $r('app.string.welcome_empty_message')
      })
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
    } else {
      Column() {
        Text($r('app.string.welcome_recent'))
          .fontSize($r('app.float.font_s'))
          .fontColor($r('app.color.text_secondary'))
          .width(UiConst.FULL)
          .margin({ bottom: $r('app.float.space_s') })
        List({ space: UiConst.AGENT_ITEM_GAP }) {
          ForEach(this.model.visibleProjects, (p: ProjectInfo) => {
            ListItem() {
              ProjectRow({
                project: p,
                touch: touch,
                onOpen: () => this.model.open(p),
                onRemove: () => this.model.remove(p),
                onDelete: () => this.model.deleteFromDisk(p)
              })
            }
          }, (p: ProjectInfo) => p.id + ':' + p.lastOpened)
        }
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .clip(false)
      }
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
    }
  }

  @Builder
  openSheet() {
    Column() {
      if (this.model.openCandidates.length === 0) {
        EmptyState({
          icon: $r('app.media.ic_folder_open'),
          title: $r('app.string.welcome_open_empty_title'),
          message: $r('app.string.welcome_open_empty_message')
        })
      } else {
        List() {
          ForEach(this.model.openCandidates, (path: string) => {
            ListItem() {
              Row({ space: $r('app.float.space_m') }) {
                Image($r('app.media.ic_folder'))
                  .width($r('app.float.icon_size'))
                  .height($r('app.float.icon_size'))
                  .fillColor($r('app.color.folder_icon'))
                Text(PathUtil.baseName(path))
                  .fontSize($r('app.float.font_m'))
                  .fontColor($r('app.color.text_primary'))
              }
              .width(UiConst.FULL)
              .height($r('app.float.list_row_touch'))
              .padding({ left: $r('app.float.space_l'), right: $r('app.float.space_l') })
              .onClick(() => this.model.openFolder(path))
            }
          }, (path: string) => path)
        }
      }
    }
    .width(UiConst.FULL)
  }
}
