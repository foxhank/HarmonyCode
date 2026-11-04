import { AppConfig } from '../../core/common/AppConfig';
import { Strings } from '../../core/common/Strings';
import { envImages, ImageState, ImageStatus } from '../../core/env/EnvImages';
import { Catalog, EnvironmentDef, ImageSource } from '../../core/project/Catalog';
import { SettingsStore, settingsStore } from '../../core/settings/SettingsStore';
import { VmPhase, vmRuntime } from '../../core/terminal/vm/VmRuntime';
import { ActionButton, ActionStyle } from '../../components/ActionButton';
import { NumberStepper } from '../../components/NumberStepper';
import { SettingRow } from '../../components/SettingRow';
import { UiConst } from '../../components/UiConst';
import { CatalogText } from '../app/CatalogText';
import { Buttons } from '../dialogs/Buttons';
import { ButtonRole, dialogs } from '../dialogs/DialogModel';
import { toasts } from '../dialogs/ToastModel';

const PERCENT: number = 100;

/** Linux environments (hiSH VM images) and the VM's CPU and memory. Self-contained settings section. */
@ComponentV2
export struct EnvironmentsSection {
  private s: SettingsStore = settingsStore;

  private vmEnvironments(): EnvironmentDef[] {
    return Catalog.environments().filter((e: EnvironmentDef) => e.isVm);
  }

  /** True while this environment's VM is starting or running in this process. */
  private inUse(env: EnvironmentDef): boolean {
    return vmRuntime.envId === env.id && vmRuntime.phase !== VmPhase.IDLE;
  }

  private async remove(env: EnvironmentDef): Promise<void> {
    if (this.inUse(env)) {
      toasts.error(Strings.get('settings_env_in_use', CatalogText.envName(env.id)));
      return;
    }
    const name = CatalogText.envName(env.id);
    const choice = await dialogs.confirm(Strings.get('settings_env_remove_title', name),
      Strings.get('settings_env_remove_message', name),
      [Buttons.cancel(), Buttons.of($r('app.string.action_remove'), ButtonRole.DANGER)]);
    if (choice === 1) {
      envImages.remove(env.id);
    }
  }

  build() {
    Column({ space: $r('app.float.space_m') }) {
      Text($r('app.string.settings_section_environments'))
        .fontSize($r('app.float.font_l'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width(UiConst.FULL)
      if (!vmRuntime.isAvailable()) {
        Text($r('app.string.settings_env_unavailable'))
          .fontSize($r('app.float.font_s'))
          .fontColor($r('app.color.danger'))
          .width(UiConst.FULL)
      }
      ForEach(this.vmEnvironments(), (env: EnvironmentDef) => {
        this.envRow(env, envImages.state(env.id))
      }, (env: EnvironmentDef) => env.id)
      SettingRow({ label: $r('app.string.settings_env_cpus') }) {
        NumberStepper({
          value: this.s.vmCpus, min: AppConfig.VM_CPUS_MIN, max: AppConfig.VM_CPUS_MAX,
          onChange: (v: number) => {
            this.s.vmCpus = v;
            this.s.save();
          }
        })
      }
      SettingRow({ label: $r('app.string.settings_env_memory') }) {
        NumberStepper({
          value: this.s.vmMemoryMb, min: AppConfig.VM_MEMORY_MIN_MB, max: AppConfig.VM_MEMORY_MAX_MB,
          step: AppConfig.VM_MEMORY_STEP_MB,
          onChange: (v: number) => {
            this.s.vmMemoryMb = v;
            this.s.save();
          }
        })
      }
      Text($r('app.string.settings_env_resources_hint'))
        .fontSize($r('app.float.font_xs'))
        .fontColor($r('app.color.text_muted'))
        .width(UiConst.FULL)
      Text($r('app.string.about_qemu'))
        .fontSize($r('app.float.font_xs'))
        .fontColor($r('app.color.text_muted'))
        .width(UiConst.FULL)
        .copyOption(CopyOptions.LocalDevice)
    }
  }

  @Builder
  envRow(env: EnvironmentDef, state: ImageState) {
    Row({ space: $r('app.float.space_m') }) {
      Column({ space: $r('app.float.space_xxs') }) {
        Text(CatalogText.envName(env.id))
          .fontSize($r('app.float.font_m'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.inUse(env) ? Strings.get('settings_env_running') : CatalogText.envStatus(env))
          .fontSize($r('app.float.font_s'))
          .fontColor($r('app.color.text_secondary'))
        if (state.status === ImageStatus.INSTALLING || state.status === ImageStatus.VERIFYING) {
          Progress({ value: state.progress * PERCENT, total: PERCENT, type: ProgressType.Linear })
            .color($r('app.color.accent'))
            .width(UiConst.FULL)
        }
        if (state.error.length > 0) {
          Text(state.error)
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.danger'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      this.envAction(env, state)
    }
    .width(UiConst.FULL)
    .padding($r('app.float.space_m'))
    .borderRadius($r('app.float.radius_m'))
    .border({ width: $r('app.float.border_width'), color: $r('app.color.border') })
    .backgroundColor($r('app.color.card_bg'))
  }

  @Builder
  envAction(env: EnvironmentDef, state: ImageState) {
    if (state.status === ImageStatus.MISSING) {
      ActionButton({
        text: env.image !== undefined && env.image.source === ImageSource.DOWNLOAD ?
          $r('app.string.settings_env_download') : $r('app.string.settings_env_install'),
        onTap: () => {
          envImages.install(env);
        }
      })
    } else if (state.status === ImageStatus.INSTALLING && env.image !== undefined &&
      env.image.source === ImageSource.DOWNLOAD) {
      ActionButton({
        text: $r('app.string.action_cancel'), kind: ActionStyle.SECONDARY,
        onTap: () => envImages.cancel(env.id)
      })
    } else if (state.status === ImageStatus.INSTALLED) {
      ActionButton({
        text: $r('app.string.action_remove'), kind: ActionStyle.DANGER, isEnabled: !this.inUse(env),
        onTap: () => {
          this.remove(env);
        }
      })
    }
  }
}
