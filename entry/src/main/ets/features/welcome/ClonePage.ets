import { projectRepository } from '../../core/project/ProjectRepository';
import { settingsStore } from '../../core/settings/SettingsStore';
import { EnvironmentDef } from '../../core/project/Catalog';
import { ActionButton, ActionStyle } from '../../components/ActionButton';
import { InputModifier } from '../../components/Modifiers';
import { PageHeader } from '../../components/PageHeader';
import { UiConst } from '../../components/UiConst';
import { appNav, Routes } from '../app/AppNavigation';
import { AppServices } from '../app/AppServices';
import { CloneModel } from './CloneModel';
import { EnvironmentPicker } from './EnvironmentPicker';

/** Get from Version Control: URL, folder name, environment, progress. */
@ComponentV2
export struct ClonePage {
  @Local model: CloneModel = new CloneModel(projectRepository, AppServices.git);
  private inputStyle: InputModifier = new InputModifier();

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.clone_title'), onBack: () => appNav.pop() })
        Scroll() {
          Column({ space: $r('app.float.space_l') }) {
            this.field($r('app.string.clone_url'), this.model.url, $r('app.string.clone_url_placeholder'),
              (v: string) => this.model.setUrl(v), InputType.URL)
            this.field($r('app.string.clone_folder'), this.model.name, $r('app.string.new_name_placeholder'),
              (v: string) => this.model.setName(v), InputType.Normal)
            if (!settingsStore.hasGitToken) {
              Text($r('app.string.clone_private_hint'))
                .fontSize($r('app.float.font_xs'))
                .fontColor($r('app.color.text_link'))
                .width(UiConst.FULL)
                .onClick(() => appNav.pushPathByName(Routes.SETTINGS, null))
            }
            Text($r('app.string.new_environment'))
              .fontSize($r('app.float.font_s'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .width(UiConst.FULL)
            EnvironmentPicker({
              environments: this.model.environments,
              selectedId: this.model.envId,
              onSelect: (env: EnvironmentDef) => this.model.selectEnvironment(env)
            })
            if (this.model.busy) {
              Column({ space: $r('app.float.space_xs') }) {
                Progress({ value: this.model.progress, total: 1, type: ProgressType.Linear })
                  .color($r('app.color.accent'))
                  .width(UiConst.FULL)
                Text(this.model.phase.length > 0 ? this.model.phase : $r('app.string.clone_connecting'))
                  .fontSize($r('app.float.font_xs'))
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
            }
            if (this.model.error.length > 0) {
              Text(this.model.error)
                .fontSize($r('app.float.font_s'))
                .fontColor($r('app.color.danger'))
                .width(UiConst.FULL)
            }
          }
          .padding($r('app.float.space_xl'))
          .constraintSize({ maxWidth: $r('app.float.form_max_width') })
        }
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
        .align(Alignment.Top)

        Row({ space: $r('app.float.space_s') }) {
          Blank()
          ActionButton({ text: $r('app.string.action_cancel'), kind: ActionStyle.SECONDARY, onTap: () => appNav.pop() })
          ActionButton({
            text: this.model.busy ? $r('app.string.clone_cloning') : $r('app.string.clone_action'),
            kind: ActionStyle.PRIMARY,
            isEnabled: this.model.canClone,
            onTap: () => this.model.clone()
          })
        }
        .width(UiConst.FULL)
        .padding($r('app.float.space_l'))
        .border({ width: { top: $r('app.float.border_width') }, color: $r('app.color.border') })
      }
      .width(UiConst.FULL)
      .height(UiConst.FULL)
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.app_bg'))
  }

  @Builder
  field(label: ResourceStr, value: string, placeholder: ResourceStr, onChange: (v: string) => void, type: InputType) {
    Column({ space: $r('app.float.space_xs') }) {
      Text(label)
        .fontSize($r('app.float.font_s'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width(UiConst.FULL)
      TextInput({ text: value, placeholder: placeholder })
        .attributeModifier(this.inputStyle)
        .type(type)
        .width(UiConst.FULL)
        .onChange(onChange)
    }
  }
}
