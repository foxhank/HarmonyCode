import { LengthMetrics } from '@kit.ArkUI';
import { PathUtil } from '../../core/fs/PathUtil';
import { ProjectInfo } from '../../core/project/ProjectInfo';
import { projectRepository } from '../../core/project/ProjectRepository';
import { ActionButton, ActionStyle } from '../../components/ActionButton';
import { EmptyState } from '../../components/EmptyState';
import { IconButton } from '../../components/IconButton';
import { InputModifier } from '../../components/Modifiers';
import { UiConst } from '../../components/UiConst';
import { appNav, Routes } from '../app/AppNavigation';
import { layoutState } from '../app/LayoutState';
import { dialogs } from '../dialogs/DialogModel';
import { toasts } from '../dialogs/ToastModel';
import { ProjectRow } from './ProjectRow';
import { WelcomeModel } from './WelcomeModel';

/** Start screen: recent projects plus New / Open / Clone, like PyCharm's welcome window. */
@ComponentV2
export struct WelcomePage {
  @Local model: WelcomeModel = new WelcomeModel(projectRepository, dialogs, toasts);
  private inputStyle: InputModifier = new InputModifier();

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
      Column({ space: $r('app.float.space_l') }) {
        this.brand()
        Blank()
        Row({ space: $r('app.float.space_s') }) {
          IconButton({
            icon: $r('app.media.ic_settings'),
            label: $r('app.string.settings_title'),
            onTap: () => appNav.pushPathByName(Routes.SETTINGS, null)
          })
          Text($r('app.string.settings_title'))
            .fontSize($r('app.float.font_m'))
            .fontColor($r('app.color.text_secondary'))
        }
        .onClick(() => appNav.pushPathByName(Routes.SETTINGS, null))
      }
      .width($r('app.float.welcome_sidebar_width'))
      .height(UiConst.FULL)
      .padding($r('app.float.space_xl'))
      .alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.sidebar_bg'))

      Divider().vertical(true).color($r('app.color.border'))

      Column({ space: $r('app.float.space_l') }) {
        Row({ space: $r('app.float.space_s') }) {
          this.searchField()
          this.actionButtons(false)
        }
        .width(UiConst.FULL)
        this.projectList(false)
      }
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      .height(UiConst.FULL)
      .padding($r('app.float.space_xl'))
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
  }

  @Builder
  phoneLayout() {
    Column({ space: $r('app.float.space_m') }) {
      Row() {
        this.brand()
        Blank()
        IconButton({
          icon: $r('app.media.ic_settings'),
          label: $r('app.string.settings_title'),
          buttonSize: $r('app.float.icon_button_size_touch'),
          onTap: () => appNav.pushPathByName(Routes.SETTINGS, null)
        })
      }
      .width(UiConst.FULL)
      this.actionButtons(true)
      if (this.model.hasProjects) {
        this.searchField()
      }
      this.projectList(true)
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .padding($r('app.float.space_l'))
  }

  // ---------- pieces ----------

  @Builder
  brand() {
    Row({ space: $r('app.float.space_m') }) {
      Image($r('app.media.ic_logo'))
        .width($r('app.float.logo_size'))
        .height($r('app.float.logo_size'))
        .fillColor($r('app.color.accent'))
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
        onTap: () => appNav.pushPathByName(Routes.CLONE, null)
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
        List() {
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
