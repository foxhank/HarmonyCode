import { AppConfig } from '../../core/common/AppConfig';
import { Strings } from '../../core/common/Strings';
import { errorMessage } from '../../core/common/Logger';
import { SettingsStore, settingsStore, ThemeMode } from '../../core/settings/SettingsStore';
import { InputModifier } from '../../components/Modifiers';
import { NumberStepper } from '../../components/NumberStepper';
import { SegmentedControl, SegmentOption } from '../../components/SegmentedControl';
import { SettingRow } from '../../components/SettingRow';
import { UiConst } from '../../components/UiConst';
import { appearance } from '../app/Appearance';
import { toasts } from '../dialogs/ToastModel';

const TAB_SIZES: number[] = [2, 4, 8];
const LANG_SYSTEM: string = '';
const LANG_EN: string = 'en';
const LANG_ZH: string = 'zh-Hans';

/** All user settings. Used as a page (from Welcome) and as an overlay (from the workbench). */
@ComponentV2
export struct SettingsPanel {
  @Local tokenDraft: string = '';
  private s: SettingsStore = settingsStore;
  private inputStyle: InputModifier = new InputModifier();

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

  private tabOptions(): SegmentOption[] {
    return TAB_SIZES.map((n: number): SegmentOption => {
      return { value: n.toString(), label: n.toString() };
    });
  }

  private commit(): void {
    this.s.save();
  }

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
    Scroll() {
      Column({ space: $r('app.float.space_xl') }) {
        // Appearance
        Column({ space: $r('app.float.space_m') }) {
          this.sectionTitle($r('app.string.settings_section_appearance'))
          SettingRow({ label: $r('app.string.settings_theme') }) {
            SegmentedControl({
              options: this.themeOptions(), selected: this.s.theme,
              onSelect: (v: string) => {
                this.s.theme = v;
                this.commit();
                appearance.applyTheme(v);
              }
            })
          }
          SettingRow({ label: $r('app.string.settings_language') }) {
            SegmentedControl({
              options: this.languageOptions(), selected: this.s.language,
              onSelect: (v: string) => {
                this.s.language = v;
                this.commit();
                appearance.applyLanguage(v);
              }
            })
          }
        }

        // Editor
        Column({ space: $r('app.float.space_m') }) {
          this.sectionTitle($r('app.string.settings_section_editor'))
          SettingRow({ label: $r('app.string.settings_font_size') }) {
            NumberStepper({
              value: this.s.fontSize, min: AppConfig.EDITOR_FONT_MIN, max: AppConfig.EDITOR_FONT_MAX,
              onChange: (v: number) => {
                this.s.fontSize = v;
                this.commit();
              }
            })
          }
          SettingRow({ label: $r('app.string.settings_tab_size') }) {
            SegmentedControl({
              options: this.tabOptions(), selected: this.s.tabSize.toString(),
              onSelect: (v: string) => {
                this.s.tabSize = Number(v);
                this.commit();
              }
            })
          }
          this.toggleRow($r('app.string.settings_word_wrap'), this.s.wordWrap, (on: boolean) => {
            this.s.wordWrap = on;
            this.commit();
          })
          this.toggleRow($r('app.string.settings_auto_save'), this.s.autoSave, (on: boolean) => {
            this.s.autoSave = on;
            this.commit();
          })
        }

        // Terminal
        Column({ space: $r('app.float.space_m') }) {
          this.sectionTitle($r('app.string.settings_section_terminal'))
          SettingRow({ label: $r('app.string.settings_font_size') }) {
            NumberStepper({
              value: this.s.terminalFontSize, min: AppConfig.EDITOR_FONT_MIN, max: AppConfig.EDITOR_FONT_MAX,
              onChange: (v: number) => {
                this.s.terminalFontSize = v;
                this.commit();
              }
            })
          }
        }

        // Git
        Column({ space: $r('app.float.space_m') }) {
          this.sectionTitle($r('app.string.settings_section_git'))
          this.textField($r('app.string.settings_git_name'), this.s.gitName, (v: string) => {
            this.s.gitName = v;
            this.commit();
          })
          this.textField($r('app.string.settings_git_email'), this.s.gitEmail, (v: string) => {
            this.s.gitEmail = v;
            this.commit();
          })
          this.textField($r('app.string.settings_git_username'), this.s.gitUsername, (v: string) => {
            this.s.gitUsername = v;
            this.commit();
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
            Text($r('app.string.settings_git_token_hint'))
              .fontSize($r('app.float.font_xs'))
              .fontColor($r('app.color.text_muted'))
              .width(UiConst.FULL)
          }
        }

        // About
        Column({ space: $r('app.float.space_s') }) {
          this.sectionTitle($r('app.string.settings_section_about'))
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
      }
      .padding($r('app.float.space_xl'))
      .constraintSize({ maxWidth: $r('app.float.form_max_width') })
    }
    .width(UiConst.FULL)
    .height(UiConst.FULL)
    .align(Alignment.Top)
  }

  @Builder
  sectionTitle(text: ResourceStr) {
    Text(text)
      .fontSize($r('app.float.font_l'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
      .width(UiConst.FULL)
  }

  @Builder
  toggleRow(label: ResourceStr, on: boolean, onChange: (on: boolean) => void) {
    Row() {
      Text(label)
        .fontSize($r('app.float.font_m'))
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
      Toggle({ type: ToggleType.Switch, isOn: on })
        .selectedColor($r('app.color.accent'))
        .onChange(onChange)
    }
    .width(UiConst.FULL)
  }

  @Builder
  textField(label: ResourceStr, value: string, onChange: (v: string) => void) {
    Column({ space: $r('app.float.space_xs') }) {
      Text(label)
        .fontSize($r('app.float.font_s'))
        .fontColor($r('app.color.text_secondary'))
        .width(UiConst.FULL)
      TextInput({ text: value })
        .attributeModifier(this.inputStyle)
        .width(UiConst.FULL)
        .onChange(onChange)
    }
  }
}
