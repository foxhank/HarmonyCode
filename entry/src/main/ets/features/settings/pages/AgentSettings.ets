import { AgentLimits } from '../../../core/agent/AgentLimits';
import { ApprovalMode } from '../../../core/agent/Approval';
import { SearchProvider } from '../../../core/agent/web/WebAccess';
import { Strings } from '../../../core/common/Strings';
import { ApiFormat } from '../../../core/llm/ProviderConfig';
import { ProviderPreset, ProviderPresets } from '../../../core/llm/ProviderPresets';
import {
  AgentSettingsStore, agentSettings, ModelChoice, ProviderEntry, TEMPERATURE_DEFAULT
} from '../../../core/settings/AgentSettingsStore';
import { NumberStepper } from '../../../components/NumberStepper';
import { SegmentedControl, SegmentOption } from '../../../components/SegmentedControl';
import { SettingRow } from '../../../components/SettingRow';
import { UiConst } from '../../../components/UiConst';
import { NavRow, SettingsGroup, TextAreaRow, TextFieldRow, ToggleRow } from '../SettingsWidgets';

const STEP_INCREMENT: number = 5;
const TEMPERATURES: number[] = [TEMPERATURE_DEFAULT, 0, 0.3, 0.7, 1];

/** Name of the string resource for an API format. */
export function formatLabelKey(format: string): string {
  if (format === ApiFormat.OPENAI_RESPONSES) {
    return 'agent_format_responses';
  }
  if (format === ApiFormat.ANTHROPIC) {
    return 'agent_format_anthropic';
  }
  return 'agent_format_chat';
}

/** Agent settings: providers (each opens its own page), default model, approvals and limits. */
@ComponentV2
export struct AgentSettings {
  @Param touch: boolean = false;
  @Event onOpenProvider: (id: string) => void = () => {
  };
  private s: AgentSettingsStore = agentSettings;

  private approvalOptions(): SegmentOption[] {
    return [
      { value: ApprovalMode.ASK, label: $r('app.string.agent_mode_ask') },
      { value: ApprovalMode.AUTO_EDIT, label: $r('app.string.agent_mode_auto_edit') },
      { value: ApprovalMode.FULL_AUTO, label: $r('app.string.agent_mode_full_auto') },
    ];
  }

  private approvalHint(): Resource {
    if (this.s.approvalMode === ApprovalMode.FULL_AUTO) {
      return $r('app.string.agent_mode_full_auto_hint');
    }
    if (this.s.approvalMode === ApprovalMode.AUTO_EDIT) {
      return $r('app.string.agent_mode_auto_edit_hint');
    }
    return $r('app.string.agent_mode_ask_hint');
  }

  private searchOptions(): SegmentOption[] {
    return [
      { value: SearchProvider.DUCKDUCKGO, label: $r('app.string.agent_search_duckduckgo') },
      { value: SearchProvider.BRAVE, label: $r('app.string.agent_search_brave') },
      { value: SearchProvider.TAVILY, label: $r('app.string.agent_search_tavily') },
      { value: SearchProvider.SEARXNG, label: $r('app.string.agent_search_searxng') },
    ];
  }

  private temperatureOptions(): SegmentOption[] {
    return TEMPERATURES.map((t: number): SegmentOption => {
      return { value: t.toString(), label: t < 0 ? Strings.get('agent_temperature_default') : t.toString() };
    });
  }

  private providerSummary(p: ProviderEntry): string {
    const key = p.hasKey ? Strings.get('agent_key_set') : Strings.get('agent_key_missing');
    return Strings.get(formatLabelKey(p.format)) + ' · ' + Strings.plural('agent_model_count', p.models.length) +
      ' · ' + key;
  }

  private add(preset: ProviderPreset): void {
    const e = this.s.addProvider(preset, Strings.get('agent_custom_provider'));
    this.onOpenProvider(e.id);
  }

  @Builder
  presetMenu() {
    Menu() {
      ForEach(ProviderPresets.all(), (p: ProviderPreset) => {
        MenuItem({ content: p.id === ProviderPresets.CUSTOM_ID ? Strings.get('agent_custom_provider') : p.name })
          .onClick(() => this.add(p))
      }, (p: ProviderPreset) => p.id)
    }
  }

  @Builder
  modelSelect() {
    Select(this.s.choices().map((c: ModelChoice): SelectOption => {
      return { value: c.label };
    }))
      .selected(Math.max(0, this.s.choices().findIndex((c: ModelChoice) =>
        c.providerId === this.s.providerId && c.modelId === this.s.modelId)))
      .value(this.s.choices().find((c: ModelChoice) =>
        c.providerId === this.s.providerId && c.modelId === this.s.modelId)?.label ?? '')
      .font({ size: $r('app.float.font_s') })
      .onSelect((index: number) => {
        const c = this.s.choices()[index];
        if (c !== undefined) {
          this.s.select(c.providerId, c.modelId);
        }
      })
  }

  build() {
    Column({ space: $r('app.float.space_xl') }) {
      SettingsGroup({ title: $r('app.string.agent_providers'), hint: $r('app.string.agent_providers_hint') }) {
        if (this.s.providers.length === 0) {
          Text($r('app.string.agent_no_providers'))
            .fontSize($r('app.float.font_s'))
            .fontColor($r('app.color.text_muted'))
            .width(UiConst.FULL)
        }
        ForEach(this.s.providers, (p: ProviderEntry) => {
          NavRow({
            icon: $r('app.media.ic_cloud'), title: p.name, subtitle: this.providerSummary(p), touch: this.touch,
            onTap: () => this.onOpenProvider(p.id)
          })
        }, (p: ProviderEntry) => p.id + ':' + p.name + ':' + p.models.length + ':' + p.hasKey + ':' + p.format)
        Button($r('app.string.agent_add_provider'))
          .fontSize($r('app.float.font_s'))
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.button_secondary_bg'))
          .fontColor($r('app.color.button_secondary_text'))
          .borderRadius($r('app.float.radius_s'))
          .bindMenu(this.presetMenu())
      }

      if (this.s.choices().length > 0) {
        SettingsGroup({ title: $r('app.string.agent_default_model') }) {
          this.modelSelect()
        }
      }

      SettingsGroup({ title: $r('app.string.agent_behaviour') }) {
        Column({ space: $r('app.float.space_xs') }) {
          SettingRow({ label: $r('app.string.agent_approval_mode') }) {
            SegmentedControl({
              options: this.approvalOptions(), selected: this.s.approvalMode,
              onSelect: (v: string) => {
                this.s.approvalMode = v;
                this.s.save();
              }
            })
          }
          Text(this.approvalHint())
            .fontSize($r('app.float.font_xs'))
            .fontColor($r('app.color.text_muted'))
            .width(UiConst.FULL)
        }
        SettingRow({ label: $r('app.string.agent_max_steps') }) {
          NumberStepper({
            value: this.s.maxSteps, min: AgentLimits.MAX_STEPS_MIN, max: AgentLimits.MAX_STEPS_MAX, step: STEP_INCREMENT,
            onChange: (v: number) => {
              this.s.maxSteps = v;
              this.s.save();
            }
          })
        }
        SettingRow({ label: $r('app.string.agent_temperature') }) {
          SegmentedControl({
            options: this.temperatureOptions(), selected: this.s.temperature.toString(),
            onSelect: (v: string) => {
              this.s.temperature = Number(v);
              this.s.save();
            }
          })
        }
        ToggleRow({
          label: $r('app.string.agent_web_tools'), hint: $r('app.string.agent_web_tools_hint'), isOn: this.s.webEnabled,
          onToggle: (on: boolean) => {
            this.s.webEnabled = on;
            this.s.save();
          }
        })
        if (this.s.webEnabled) {
          Column({ space: $r('app.float.space_xs') }) {
            SettingRow({ label: $r('app.string.agent_search_provider') }) {
              SegmentedControl({
                options: this.searchOptions(), selected: this.s.searchProvider,
                onSelect: (v: string) => this.s.setSearchProvider(v)
              })
            }
            if (SearchProvider.needsKey(this.s.searchProvider)) {
              TextFieldRow({
                label: $r('app.string.agent_search_key'), value: '', inputType: InputType.Password,
                placeholder: this.s.hasSearchKey ? $r('app.string.agent_key_set') : $r('app.string.agent_search_key_placeholder'),
                onChanged: (v: string) => this.s.setSearchKey(v)
              })
            }
            if (SearchProvider.needsEndpoint(this.s.searchProvider)) {
              TextFieldRow({
                label: $r('app.string.agent_search_endpoint'), value: this.s.searchEndpoint,
                placeholder: $r('app.string.agent_search_endpoint_placeholder'), inputType: InputType.URL,
                hint: $r('app.string.agent_search_endpoint_hint'),
                onChanged: (v: string) => {
                  this.s.searchEndpoint = v.trim();
                  this.s.save();
                }
              })
            }
          }
        }
        TextAreaRow({
          label: $r('app.string.agent_custom_instructions'), value: this.s.customInstructions,
          placeholder: $r('app.string.agent_custom_instructions_placeholder'),
          hint: $r('app.string.agent_custom_instructions_hint'),
          onChanged: (v: string) => {
            this.s.customInstructions = v;
            this.s.save();
          }
        })
      }
    }
    .width(UiConst.FULL)
  }
}
