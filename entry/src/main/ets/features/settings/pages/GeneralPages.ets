import { AppConfig } from '../../../core/common/AppConfig';
import { errorMessage } from '../../../core/common/Logger';
import { Strings } from '../../../core/common/Strings';
import { SettingsStore, settingsStore, ThemeMode } from '../../../core/settings/SettingsStore';
import { InputModifier } from '../../../components/Modifiers';
import { NumberStepper } from '../../../components/NumberStepper';
import { SegmentedControl, SegmentOption } from '../../../components/SegmentedControl';
import { SettingRow } from '../../../components/SettingRow';
import { UiConst } from '../../../components/UiConst';
import { appearance } from '../../app/Appearance';
import { toasts } from '../../dialogs/ToastModel';
import { EnvironmentsSection } from '../EnvironmentsSection';
import { SettingsGroup, TextFieldRow, ToggleRow } from '../SettingsWidgets';

const TAB_SIZES: number[] = [2, 4, 8];
const LANG_SYSTEM: string = '';
const LANG_EN: string = 'en';
const LANG_ZH: string = 'zh-Hans';

/** Theme and language. */
@ComponentV2
export struct AppearanceSettings {
  private s: SettingsStore = settingsStore;

  private themeOptions(): SegmentOption[] {
    return [
      { value: ThemeMode.SYSTEM, label: $r('app.string.settings_theme_system') },
      { value: ThemeMode.LIGHT, label: $r('app.string.settings_theme_light') },
      { value: ThemeMode.DARK, label: $r('app.string.settings_theme_dark') },
    ];
  }

  private languageOptions(): SegmentOption[] {
    return [
      { value: LANG_SYSTEM, label: $r('app.string.settings_language_system') },
      { value: LANG_EN, label: $r('app.string.lang_en') },
      { value: LANG_ZH, label: $r('app.string.lang_zh_hans') },
    ];
  }

  build() {
    SettingsGroup() {
      SettingRow({ label: $r('app.string.settings_theme') }) {
        SegmentedControl({
          options: this.themeOptions(), selected: this.s.theme,
          onSelect: (v: string) => {
            this.s.theme = v;
            this.s.save();
            appearance.applyTheme(v);
          }
        })
      }
      SettingRow({ label: $r('app.string.settings_language') }) {
        SegmentedControl({
          options: this.languageOptions(), selected: this.s.language,
          onSelect: (v: string) => {
            this.s.language = v;
            this.s.save();
            appearance.applyLanguage(v);
          }
        })
      }
    }
  }
}

/** Where code is built and run: the Linux environments. */
@ComponentV2
export struct CompilerSettings {
  build() {
    Column({ space: $r('app.float.space_l') }) {
      Text($r('app.string.settings_compiler_hint'))
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.text_secondary'))
        .width(UiConst.FULL)
      EnvironmentsSection()
    }
    .width(UiConst.FULL)
  }
}

/** Editor font, indentation and saving. */
@ComponentV2
export struct EditorSettings {
  private s: SettingsStore = settingsStore;

  private tabOptions(): SegmentOption[] {
    return TAB_SIZES.map((n: number): SegmentOption => {
      return { value: n.toString(), label: n.toString() };
    });
  }

  build() {
    SettingsGroup() {
      SettingRow({ label: $r('app.string.settings_font_size') }) {
        NumberStepper({
          value: this.s.fontSize, min: AppConfig.EDITOR_FONT_MIN, max: AppConfig.EDITOR_FONT_MAX,
          onChange: (v: number) => {
            this.s.fontSize = v;
            this.s.save();
          }
        })
      }
      SettingRow({ label: $r('app.string.settings_tab_size') }) {
        SegmentedControl({
          options: this.tabOptions(), selected: this.s.tabSize.toString(),
          onSelect: (v: string) => {
            this.s.tabSize = Number(v);
            this.s.save();
          }
        })
      }
      ToggleRow({
        label: $r('app.string.settings_word_wrap'), isOn: this.s.wordWrap, onToggle: (on: boolean) => {
          this.s.wordWrap = on;
          this.s.save();
        }
      })
      ToggleRow({
        label: $r('app.string.settings_auto_save'), isOn: this.s.autoSave, onToggle: (on: boolean) => {
          this.s.autoSave = on;
          this.s.save();
        }
      })
    }
  }
}

/** Terminal font. */
@ComponentV2
export struct TerminalSettings {
  private s: SettingsStore = settingsStore;

  build() {
    SettingsGroup() {
      SettingRow({ label: $r('app.string.settings_font_size') }) {
        NumberStepper({
          value: this.s.terminalFontSize, min: AppConfig.EDITOR_FONT_MIN, max: AppConfig.EDITOR_FONT_MAX,
          onChange: (v: number) => {
            this.s.terminalFontSize = v;
            this.s.save();
          }
        })
      }
    }
  }
}

/** Commit identity and HTTPS credentials. */
@ComponentV2
export struct GitSettings {
  @Local tokenDraft: string = '';
  private s: SettingsStore = settingsStore;
  private inputStyle: InputModifier = new InputModifier();

  private saveToken(): void {
    try {
      this.s.setGitToken(this.tokenDraft.trim());
      this.tokenDraft = '';
      toasts.info(Strings.get(this.s.hasGitToken ? 'settings_token_saved' : 'settings_token_cleared'));
    } catch (e) {
      toasts.error(errorMessage(e as Error));
    }
  }

  build() {
    Column({ space: $r('app.float.space_xl') }) {
      SettingsGroup({ title: $r('app.string.settings_git_identity') }) {
        TextFieldRow({
          label: $r('app.string.settings_git_name'), value: this.s.gitName, onChanged: (v: string) => {
            this.s.gitName = v;
            this.s.save();
          }
        })
        TextFieldRow({
          label: $r('app.string.settings_git_email'), value: this.s.gitEmail, inputType: InputType.Email,
          onChanged: (v: string) => {
            this.s.gitEmail = v;
            this.s.save();
          }
        })
      }
      SettingsGroup({ title: $r('app.string.settings_git_credentials'), hint: $r('app.string.settings_git_token_hint') }) {
        TextFieldRow({
          label: $r('app.string.settings_git_username'), value: this.s.gitUsername, onChanged: (v: string) => {
            this.s.gitUsername = v;
            this.s.save();
          }
        })
        Column({ space: $r('app.float.space_xs') }) {
          Text(this.s.hasGitToken ? $r('app.string.settings_git_token_set') : $r('app.string.settings_git_token'))
            .fontSize($r('app.float.font_s'))
            .fontColor($r('app.color.text_secondary'))
            .width(UiConst.FULL)
          Row({ space: $r('app.float.space_s') }) {
            TextInput({ text: this.tokenDraft, placeholder: $r('app.string.settings_git_token_placeholder') })
              .attributeModifier(this.inputStyle)
              .type(InputType.Password)
              .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
              .onChange((v: string) => {
                this.tokenDraft = v;
              })
            Button($r('app.string.action_save'))
              .fontSize($r('app.float.font_s'))
              .height($r('app.float.input_height'))
              .backgroundColor($r('app.color.button_primary_bg'))
              .fontColor($r('app.color.text_on_accent'))
              .borderRadius($r('app.float.radius_s'))
              .onClick(() => this.saveToken())
          }
        }
        .width(UiConst.FULL)
      }
    }
    .width(UiConst.FULL)
  }
}

/** Credits and licenses. */
@ComponentV2
export struct AboutSettings {
  build() {
    Column({ space: $r('app.float.space_s') }) {
      Text($r('app.string.app_name'))
        .fontSize($r('app.float.font_l'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width(UiConst.FULL)
      Text($r('app.string.about_hish'))
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.text_secondary'))
        .width(UiConst.FULL)
      Text($r('app.string.about_hish_url'))
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.text_link'))
        .width(UiConst.FULL)
        .copyOption(CopyOptions.LocalDevice)
      Text($r('app.string.about_libraries'))
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.text_secondary'))
        .width(UiConst.FULL)
    }
    .width(UiConst.FULL)
  }
}
