import { errorMessage } from '../../../core/common/Logger';
import { Strings } from '../../../core/common/Strings';
import { ApiFormat, ModelDefaults } from '../../../core/llm/ProviderConfig';
import { AgentSettingsStore, agentSettings, ModelEntry, ProviderEntry } from '../../../core/settings/AgentSettingsStore';
import { MONO_FONT } from '../../../components/Fonts';
import { IconButton } from '../../../components/IconButton';
import { InputModifier } from '../../../components/Modifiers';
import { SegmentedControl, SegmentOption } from '../../../components/SegmentedControl';
import { UiConst } from '../../../components/UiConst';
import { LlmServices } from '../../agent/LlmServices';
import { Buttons } from '../../dialogs/Buttons';
import { ButtonRole, dialogs } from '../../dialogs/DialogModel';
import { toasts } from '../../dialogs/ToastModel';
import { SettingsGroup, TextAreaRow, TextFieldRow, ToggleRow } from '../SettingsWidgets';

const TOKENS_PER_K: number = 1000;

/** Result of the last connection test. */
class ProbeState {
  static readonly IDLE: string = 'idle';
  static readonly RUNNING: string = 'running';
  static readonly OK: string = 'ok';
  static readonly FAILED: string = 'failed';
}

/** One provider: endpoint, format, API key, headers and models. */
@ComponentV2
export struct ProviderSettings {
  @Param @Require providerId: string;
  @Event onDeleted: () => void = () => {
  };
  @Local keyDraft: string = '';
  @Local probe: string = ProbeState.IDLE;
  @Local probeMessage: string = '';
  private s: AgentSettingsStore = agentSettings;
  private inputStyle: InputModifier = new InputModifier();

  private get p(): ProviderEntry | undefined {
    return this.s.provider(this.providerId);
  }

  private formatOptions(): SegmentOption[] {
    return [
      { value: ApiFormat.OPENAI_CHAT, label: $r('app.string.agent_format_chat') },
      { value: ApiFormat.OPENAI_RESPONSES, label: $r('app.string.agent_format_responses') },
      { value: ApiFormat.ANTHROPIC, label: $r('app.string.agent_format_anthropic') },
    ];
  }

  private commit(): void {
    this.s.save();
  }

  private saveKey(p: ProviderEntry): void {
    try {
      this.s.setKey(p.id, this.keyDraft);
      this.keyDraft = '';
      toasts.info(Strings.get(p.hasKey ? 'agent_key_saved' : 'agent_key_cleared'));
    } catch (e) {
      toasts.error(errorMessage(e as Error));
    }
  }

  private addModel(p: ProviderEntry): void {
    const m = new ModelEntry();
    m.contextWindow = ModelDefaults.CONTEXT_WINDOW;
    p.models = p.models.concat([m]);
    this.commit();
  }

  private removeModel(p: ProviderEntry, m: ModelEntry): void {
    p.models = p.models.filter((x: ModelEntry) => x !== m);
    this.commit();
  }

  private async test(p: ProviderEntry): Promise<void> {
    const model = p.models.find((m: ModelEntry) => m.id.trim().length > 0);
    if (model === undefined) {
      this.probe = ProbeState.FAILED;
      this.probeMessage = Strings.get('agent_test_no_model');
      return;
    }
    const resolved = this.s.resolveProvider(p.id, model.id);
    if (resolved === null) {
      return;
    }
    this.probe = ProbeState.RUNNING;
    this.probeMessage = '';
    try {
      const reply = await LlmServices.probe(resolved.provider, resolved.model);
      this.probe = ProbeState.OK;
      this.probeMessage = Strings.get('agent_test_ok', model.id, reply.length > 0 ? reply : '—');
    } catch (e) {
      this.probe = ProbeState.FAILED;
      this.probeMessage = errorMessage(e as Error);
    }
  }

  private async remove(p: ProviderEntry): Promise<void> {
    const choice = await dialogs.confirm(Strings.get('agent_remove_provider_title', p.name),
      Strings.get('agent_remove_provider_message'),
      [Buttons.cancel(), Buttons.of($r('app.string.action_remove'), ButtonRole.DANGER)]);
    if (choice === 1) {
      this.s.removeProvider(p.id);
      this.onDeleted();
    }
  }

  @Builder
  modelCard(p: ProviderEntry, m: ModelEntry) {
    Column({ space: $r('app.float.space_s') }) {
      Row({ space: $r('app.float.space_s') }) {
        TextInput({ text: m.id, placeholder: $r('app.string.agent_model_id_placeholder') })
          .attributeModifier(this.inputStyle)
          .fontFamily(MONO_FONT)
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
          .onChange((v: string) => {
            m.id = v.trim();
            this.commit();
          })
        IconButton({
          icon: $r('app.media.ic_remove'), label: $r('app.string.agent_remove_model'),
          onTap: () => this.removeModel(p, m)
        })
      }
      Row({ space: $r('app.float.space_s') }) {
        TextInput({ text: m.name, placeholder: $r('app.string.agent_model_name_placeholder') })
          .attributeModifier(this.inputStyle)
          .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
          .onChange((v: string) => {
            m.name = v;
            this.commit();
          })
        TextInput({ text: Math.round(m.contextWindow / TOKENS_PER_K).toString() })
          .attributeModifier(this.inputStyle)
          .type(InputType.Number)
          .width($r('app.float.agent_number_field_width'))
          .onChange((v: string) => {
            const k = Number(v);
            if (k > 0) {
              m.contextWindow = Math.round(k * TOKENS_PER_K);
              this.commit();
            }
          })
        Text($r('app.string.agent_context_k'))
          .fontSize($r('app.float.font_xs'))
          .fontColor($r('app.color.text_muted'))
      }
      ToggleRow({
        label: $r('app.string.agent_model_reasoning'), hint: $r('app.string.agent_model_reasoning_hint'),
        isOn: m.reasoning, onToggle: (on: boolean) => {
          m.reasoning = on;
          this.commit();
        }
      })
    }
    .width(UiConst.FULL)
    .padding($r('app.float.space_s'))
    .borderRadius($r('app.float.radius_m'))
    .border({ width: $r('app.float.border_width'), color: $r('app.color.border') })
  }

  @Builder
  content(p: ProviderEntry) {
    Column({ space: $r('app.float.space_xl') }) {
      SettingsGroup({ title: $r('app.string.agent_endpoint') }) {
        TextFieldRow({
          label: $r('app.string.agent_provider_name'), value: p.name, onChanged: (v: string) => {
            p.name = v;
            this.commit();
          }
        })
        Column({ space: $r('app.float.space_xs') }) {
          Text($r('app.string.agent_api_format'))
            .fontSize($r('app.float.font_s'))
            .fontColor($r('app.color.text_secondary'))
            .width(UiConst.FULL)
          SegmentedControl({
            options: this.formatOptions(), selected: p.format, onSelect: (v: string) => {
              p.format = v;
              this.commit();
            }
          })
        }
        .width(UiConst.FULL)
        .alignItems(HorizontalAlign.Start)
        TextFieldRow({
          label: $r('app.string.agent_base_url'), value: p.baseUrl, inputType: InputType.URL,
          placeholder: $r('app.string.agent_base_url_placeholder'), hint: $r('app.string.agent_base_url_hint'),
          onChanged: (v: string) => {
            p.baseUrl = v.trim();
            this.commit();
          }
        })
        Column({ space: $r('app.float.space_xs') }) {
          Text(p.hasKey ? $r('app.string.agent_api_key_set') : $r('app.string.agent_api_key'))
            .fontSize($r('app.float.font_s'))
            .fontColor($r('app.color.text_secondary'))
            .width(UiConst.FULL)
          Row({ space: $r('app.float.space_s') }) {
            TextInput({ text: this.keyDraft, placeholder: $r('app.string.agent_api_key_placeholder') })
              .attributeModifier(this.inputStyle)
              .type(InputType.Password)
              .layoutWeight(UiConst.LAYOUT_WEIGHT_FILL)
              .onChange((v: string) => {
                this.keyDraft = v;
              })
            Button($r('app.string.action_save'))
              .fontSize($r('app.float.font_s'))
              .height($r('app.float.input_height'))
              .backgroundColor($r('app.color.button_primary_bg'))
              .fontColor($r('app.color.text_on_accent'))
              .borderRadius($r('app.float.radius_s'))
              .onClick(() => this.saveKey(p))
          }
          Text($r('app.string.agent_api_key_hint'))
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.text_muted'))
            .width(UiConst.FULL)
        }
        TextAreaRow({
          label: $r('app.string.agent_headers'), value: p.headers, placeholder: $r('app.string.agent_headers_placeholder'),
          onChanged: (v: string) => {
            p.headers = v;
            this.commit();
          }
        })
      }

      SettingsGroup({ title: $r('app.string.agent_models'), hint: $r('app.string.agent_models_hint') }) {
        ForEach(p.models, (m: ModelEntry) => {
          this.modelCard(p, m)
        }, (m: ModelEntry) => p.id + ':' + m.uid)
        Button($r('app.string.agent_add_model'))
          .fontSize($r('app.float.font_s'))
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.button_secondary_bg'))
          .fontColor($r('app.color.button_secondary_text'))
          .borderRadius($r('app.float.radius_s'))
          .onClick(() => this.addModel(p))
      }

      SettingsGroup({ title: $r('app.string.agent_test_title') }) {
        Row({ space: $r('app.float.space_s') }) {
          Button($r('app.string.agent_test_action'))
            .fontSize($r('app.float.font_s'))
            .height($r('app.float.button_height'))
            .backgroundColor($r('app.color.button_secondary_bg'))
            .fontColor($r('app.color.button_secondary_text'))
            .borderRadius($r('app.float.radius_s'))
            .enabled(this.probe !== ProbeState.RUNNING)
            .onClick(() => this.test(p))
          if (this.probe === ProbeState.RUNNING) {
            LoadingProgress()
              .width($r('app.float.icon_size'))
              .height($r('app.float.icon_size'))
              .color($r('app.color.accent'))
          }
        }
        if (this.probeMessage.length > 0) {
          Text(this.probeMessage)
            .fontSize($r('app.float.font_s'))
            .fontColor(this.probe === ProbeState.OK ? $r('app.color.git_added') : $r('app.color.danger'))
            .copyOption(CopyOptions.LocalDevice)
            .width(UiConst.FULL)
        }
      }

      Button($r('app.string.agent_remove_provider'))
        .fontSize($r('app.float.font_s'))
        .height($r('app.float.button_height'))
        .backgroundColor($r('app.color.button_secondary_bg'))
        .fontColor($r('app.color.danger'))
        .borderRadius($r('app.float.radius_s'))
        .onClick(() => this.remove(p))
    }
    .width(UiConst.FULL)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      if (this.p !== undefined) {
        this.content(this.p as ProviderEntry)
      }
    }
    .width(UiConst.FULL)
  }
}
