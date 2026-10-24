import { projectRepository } from '../../core/project/ProjectRepository';
import { ActionButton, ActionStyle } from '../../components/ActionButton';
import { InputModifier } from '../../components/Modifiers';
import { PageHeader } from '../../components/PageHeader';
import { UiConst } from '../../components/UiConst';
import { MONO_FONT } from '../../components/Fonts';
import { appNav } from '../app/AppNavigation';
import { AppServices } from '../app/AppServices';
import { layoutState } from '../app/LayoutState';
import { EnvironmentDef } from '../../core/project/Catalog';
import { EnvironmentPicker } from './EnvironmentPicker';
import { NewProjectModel } from './NewProjectModel';
import { TemplatePicker } from './TemplatePicker';

/** New Project: template on the left, settings on the right (stacked on phones). */
@ComponentV2
export struct NewProjectPage {
  @Local model: NewProjectModel = new NewProjectModel(projectRepository, AppServices.git);
  private inputStyle: InputModifier = new InputModifier();

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.new_title'), onBack: () => appNav.pop() })
        if (layoutState.isPhone) {
          Scroll() {
            Column({ space: $r('app.float.space_l') }) {
              this.nameField()
              this.label($r('app.string.new_template'))
              TemplatePicker({
                templates: this.model.templates, selectedId: this.model.templateId, compact: true,
                onSelect: (id: string) => this.model.selectTemplate(id)
              })
              this.settingsBody()
            }
            .padding($r('app.float.space_l'))
          }
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
          .align(Alignment.Top)
        } else {
          Row() {
            Column() {
              this.label($r('app.string.new_template'))
              TemplatePicker({
                templates: this.model.templates, selectedId: this.model.templateId,
                onSelect: (id: string) => this.model.selectTemplate(id)
              })
                .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
            }
            .width($r('app.float.new_project_list_width'))
            .height(UiConst.FULL)
            .padding($r('app.float.space_l'))
            .backgroundColor($r('app.color.sidebar_bg'))

            Scroll() {
              Column({ space: $r('app.float.space_l') }) {
                this.nameField()
                this.settingsBody()
              }
              .padding($r('app.float.space_xl'))
              .constraintSize({ maxWidth: $r('app.float.form_max_width') })
            }
            .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
            .height(UiConst.FULL)
            .align(Alignment.TopStart)
          }
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        }
        this.footer()
      }
      .width(UiConst.FULL)
      .height(UiConst.FULL)
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.app_bg'))
  }

  @Builder
  label(text: ResourceStr) {
    Text(text)
      .fontSize($r('app.float.font_s'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width(UiConst.FULL)
      .margin({ bottom: $r('app.float.space_xs') })
  }

  @Builder
  nameField() {
    Column() {
      this.label($r('app.string.new_name'))
      TextInput({ text: this.model.name, placeholder: $r('app.string.new_name_placeholder') })
        .attributeModifier(this.inputStyle)
        .width(UiConst.FULL)
        .defaultFocus(true)
        .onChange((v: string) => {
          this.model.name = v;
        })
        .onSubmit(() => this.model.create())
      if (this.model.folderPreview.length > 0) {
        Text($r('app.string.new_location', this.model.folderPreview))
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.text_muted'))
          .width(UiConst.FULL)
          .margin({ top: $r('app.float.space_xs') })
      }
    }
  }

  @Builder
  settingsBody() {
    Column() {
      this.label($r('app.string.new_environment'))
      EnvironmentPicker({
        environments: this.model.environments,
        selectedId: this.model.envId,
        onSelect: (env: EnvironmentDef) => this.model.selectEnvironment(env)
      })
      if (this.model.installPreview.length > 0) {
        Column({ space: $r('app.float.space_xs') }) {
          Text($r('app.string.new_packages'))
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.text_secondary'))
          Text(this.model.installPreview)
            .fontFamily(MONO_FONT)
            .fontSize($r('app.float.font_s'))
            .fontColor($r('app.color.text_primary'))
            .padding($r('app.float.space_s'))
            .backgroundColor($r('app.color.code_bg'))
            .borderRadius($r('app.float.radius_s'))
            .width(UiConst.FULL)
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ top: $r('app.float.space_s') })
      }
    }
    Row() {
      Column() {
        Text($r('app.string.new_init_git'))
          .fontSize($r('app.float.font_m'))
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.new_init_git_detail'))
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      Toggle({ type: ToggleType.Switch, isOn: this.model.initGit })
        .selectedColor($r('app.color.accent'))
        .onChange((on: boolean) => {
          this.model.initGit = on;
        })
    }
    .width(UiConst.FULL)
    if (this.model.error.length > 0) {
      Text(this.model.error)
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.danger'))
        .width(UiConst.FULL)
    }
  }

  @Builder
  footer() {
    Row({ space: $r('app.float.space_s') }) {
      Blank()
      ActionButton({ text: $r('app.string.action_cancel'), kind: ActionStyle.SECONDARY, onTap: () => appNav.pop() })
      ActionButton({
        text: this.model.busy ? $r('app.string.new_creating') : $r('app.string.action_create'),
        kind: ActionStyle.PRIMARY,
        isEnabled: this.model.canCreate,
        onTap: () => this.model.create()
      })
    }
    .width(UiConst.FULL)
    .padding($r('app.float.space_l'))
    .border({ width: { top: $r('app.float.border_width') }, color: $r('app.color.border') })
  }
}
