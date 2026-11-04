import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AgentLimits } from '../agent/AgentLimits';
import { ApprovalMode } from '../agent/Approval';
import { SearchProvider, WebSettings } from '../agent/web/WebAccess';
import { ModelDefaults, ModelInfo, ProviderConfig } from '../llm/ProviderConfig';
import { ProviderPreset } from '../llm/ProviderPresets';
import { SecretStore } from './SecretStore';

const PREFS_NAME: string = 'agent';
const KEY_PROVIDERS: string = 'providers';
const KEY_PROVIDER_ID: string = 'providerId';
const KEY_MODEL_ID: string = 'modelId';
const KEY_APPROVAL: string = 'approvalMode';
const KEY_MAX_STEPS: string = 'maxSteps';
const KEY_TEMPERATURE: string = 'temperature';
const KEY_INSTRUCTIONS: string = 'customInstructions';
const KEY_WEB_ENABLED: string = 'webEnabled';
const KEY_SEARCH_PROVIDER: string = 'searchProvider';
const KEY_SEARCH_ENDPOINT: string = 'searchEndpoint';
const SECRET_PREFIX: string = 'harmonycode.agent.key.';
const SEARCH_SECRET_PREFIX: string = 'harmonycode.search.key.';
/** Stored temperature meaning "use the model's default". */
export const TEMPERATURE_DEFAULT: number = -1;

/** A model as edited in Settings. */
@ObservedV2
export class ModelEntry {
  private static nextUid: number = 1;
  /** Stable identity for list rendering (not saved). */
  readonly uid: number = ModelEntry.nextUid++;
  @Trace id: string = '';
  @Trace name: string = '';
  @Trace contextWindow: number = ModelDefaults.CONTEXT_WINDOW;
  @Trace maxOutputTokens: number = 0;
  @Trace reasoning: boolean = false;

  static from(m: ModelInfo): ModelEntry {
    const e = new ModelEntry();
    e.id = m.id;
    e.name = m.name;
    e.contextWindow = m.contextWindow > 0 ? m.contextWindow : ModelDefaults.CONTEXT_WINDOW;
    e.maxOutputTokens = m.maxOutputTokens;
    e.reasoning = m.reasoning;
    return e;
  }

  toInfo(): ModelInfo {
    return {
      id: this.id.trim(), name: this.name.trim(), contextWindow: this.contextWindow,
      maxOutputTokens: this.maxOutputTokens, reasoning: this.reasoning
    };
  }
}

/** Persisted form of a provider (the API key lives in the Asset Store, not here). */
interface ProviderJson {
  id: string;
  name: string;
  format: string;
  baseUrl: string;
  headers: string;
  models: ModelInfo[];
}

/** A provider as edited in Settings. */
@ObservedV2
export class ProviderEntry {
  @Trace id: string = '';
  @Trace name: string = '';
  @Trace format: string = '';
  @Trace baseUrl: string = '';
  /** Extra headers, one "Name: value" per line. */
  @Trace headers: string = '';
  @Trace models: ModelEntry[] = [];
  @Trace hasKey: boolean = false;

  headerMap(): Record<string, string> {
    const out: Record<string, string> = {};
    for (const line of this.headers.split('\n')) {
      const i = line.indexOf(':');
      if (i > 0) {
        const k = line.substring(0, i).trim();
        if (k.length > 0) {
          out[k] = line.substring(i + 1).trim();
        }
      }
    }
    return out;
  }

  toJson(): ProviderJson {
    return {
      id: this.id, name: this.name, format: this.format, baseUrl: this.baseUrl, headers: this.headers,
      models: this.models.map((m: ModelEntry) => m.toInfo())
    };
  }

  static fromJson(j: ProviderJson): ProviderEntry {
    const p = new ProviderEntry();
    p.id = j.id;
    p.name = j.name;
    p.format = j.format;
    p.baseUrl = j.baseUrl;
    p.headers = j.headers ?? '';
    p.models = (j.models ?? []).map((m: ModelInfo) => ModelEntry.from(m));
    return p;
  }
}

/** A selectable model, for pickers. */
export interface ModelChoice {
  providerId: string;
  modelId: string;
  label: string;
}

/** The model the agent should use, ready for the model layer. */
export interface ResolvedModel {
  provider: ProviderConfig;
  model: ModelInfo;
}

/** Agent preferences: providers, models, the chosen model and behaviour limits. */
@ObservedV2
export class AgentSettingsStore {
  @Trace providers: ProviderEntry[] = [];
  @Trace providerId: string = '';
  @Trace modelId: string = '';
  @Trace approvalMode: string = ApprovalMode.ASK;
  @Trace maxSteps: number = AgentLimits.MAX_STEPS_DEFAULT;
  @Trace temperature: number = TEMPERATURE_DEFAULT;
  @Trace customInstructions: string = '';
  /** web_search / web_fetch offered to the agent. */
  @Trace webEnabled: boolean = true;
  @Trace searchProvider: string = SearchProvider.DUCKDUCKGO;
  /** SearXNG instance address. */
  @Trace searchEndpoint: string = '';
  /** Whether the current search provider has its API key stored. */
  @Trace hasSearchKey: boolean = false;
  private prefs: preferences.Preferences | null = null;

  get loaded(): boolean {
    return this.prefs !== null;
  }

  /** Loads once; later calls do nothing. */
  ensureLoaded(ctx: common.Context): void {
    if (this.prefs !== null) {
      return;
    }
    const p = preferences.getPreferencesSync(ctx, { name: PREFS_NAME });
    this.prefs = p;
    try {
      const list = JSON.parse(p.getSync(KEY_PROVIDERS, '[]') as string) as ProviderJson[];
      this.providers = list.map((j: ProviderJson) => {
        const e = ProviderEntry.fromJson(j);
        e.hasKey = SecretStore.get(SECRET_PREFIX + e.id).length > 0;
        return e;
      });
    } catch (e) {
      this.providers = [];
    }
    this.providerId = p.getSync(KEY_PROVIDER_ID, '') as string;
    this.modelId = p.getSync(KEY_MODEL_ID, '') as string;
    this.approvalMode = p.getSync(KEY_APPROVAL, ApprovalMode.ASK) as string;
    this.maxSteps = p.getSync(KEY_MAX_STEPS, AgentLimits.MAX_STEPS_DEFAULT) as number;
    this.temperature = p.getSync(KEY_TEMPERATURE, TEMPERATURE_DEFAULT) as number;
    this.customInstructions = p.getSync(KEY_INSTRUCTIONS, '') as string;
    this.webEnabled = p.getSync(KEY_WEB_ENABLED, true) as boolean;
    this.searchProvider = p.getSync(KEY_SEARCH_PROVIDER, SearchProvider.DUCKDUCKGO) as string;
    if (SearchProvider.all().indexOf(this.searchProvider) < 0) {
      this.searchProvider = SearchProvider.DUCKDUCKGO;
    }
    this.searchEndpoint = p.getSync(KEY_SEARCH_ENDPOINT, '') as string;
    this.hasSearchKey = SecretStore.get(SEARCH_SECRET_PREFIX + this.searchProvider).length > 0;
    this.fixSelection();
  }

  save(): void {
    const p = this.prefs;
    if (p === null) {
      return;
    }
    this.fixSelection();
    p.putSync(KEY_PROVIDERS, JSON.stringify(this.providers.map((e: ProviderEntry) => e.toJson())));
    p.putSync(KEY_PROVIDER_ID, this.providerId);
    p.putSync(KEY_MODEL_ID, this.modelId);
    p.putSync(KEY_APPROVAL, this.approvalMode);
    p.putSync(KEY_MAX_STEPS, this.maxSteps);
    p.putSync(KEY_TEMPERATURE, this.temperature);
    p.putSync(KEY_INSTRUCTIONS, this.customInstructions);
    p.putSync(KEY_WEB_ENABLED, this.webEnabled);
    p.putSync(KEY_SEARCH_PROVIDER, this.searchProvider);
    p.putSync(KEY_SEARCH_ENDPOINT, this.searchEndpoint);
    p.flush();
  }

  setSearchProvider(provider: string): void {
    this.searchProvider = provider;
    this.hasSearchKey = SecretStore.get(SEARCH_SECRET_PREFIX + provider).length > 0;
    this.save();
  }

  setSearchKey(key: string): void {
    SecretStore.set(SEARCH_SECRET_PREFIX + this.searchProvider, key.trim());
    this.hasSearchKey = key.trim().length > 0;
  }

  /** What the web tools use, read at call time so changes apply to running sessions. */
  webSettings(): WebSettings {
    return {
      provider: this.searchProvider,
      apiKey: SearchProvider.needsKey(this.searchProvider) ? SecretStore.get(SEARCH_SECRET_PREFIX + this.searchProvider) : '',
      endpoint: this.searchEndpoint
    };
  }

  provider(id: string): ProviderEntry | undefined {
    return this.providers.find((e: ProviderEntry) => e.id === id);
  }

  /** Adds a provider from a preset, with a unique id. */
  addProvider(preset: ProviderPreset, fallbackName: string): ProviderEntry {
    const e = new ProviderEntry();
    let id = preset.id;
    let n = 2;
    while (this.provider(id) !== undefined) {
      id = preset.id + '-' + n;
      n++;
    }
    e.id = id;
    e.name = preset.name.length > 0 ? preset.name : fallbackName;
    e.format = preset.format;
    e.baseUrl = preset.baseUrl;
    e.models = preset.models.map((m: ModelInfo) => ModelEntry.from(m));
    this.providers = this.providers.concat([e]);
    this.save();
    return e;
  }

  removeProvider(id: string): void {
    SecretStore.remove(SECRET_PREFIX + id);
    this.providers = this.providers.filter((e: ProviderEntry) => e.id !== id);
    this.save();
  }

  setKey(id: string, key: string): void {
    SecretStore.set(SECRET_PREFIX + id, key.trim());
    const e = this.provider(id);
    if (e !== undefined) {
      e.hasKey = key.trim().length > 0;
    }
  }

  select(providerId: string, modelId: string): void {
    this.providerId = providerId;
    this.modelId = modelId;
    this.save();
  }

  /** Every model of every provider. */
  choices(): ModelChoice[] {
    const out: ModelChoice[] = [];
    for (const p of this.providers) {
      for (const m of p.models) {
        if (m.id.trim().length > 0) {
          out.push({ providerId: p.id, modelId: m.id, label: p.name + ' · ' + (m.name.length > 0 ? m.name : m.id) });
        }
      }
    }
    return out;
  }

  /** The selected provider and model with its secret, or null when nothing usable is set up. */
  resolve(): ResolvedModel | null {
    return this.resolveProvider(this.providerId, this.modelId);
  }

  /** A provider and one of its models, ready for the model layer. */
  resolveProvider(providerId: string, modelId: string): ResolvedModel | null {
    const p = this.provider(providerId);
    if (p === undefined) {
      return null;
    }
    const m = p.models.find((x: ModelEntry) => x.id === modelId);
    if (m === undefined) {
      return null;
    }
    const models = p.models.map((x: ModelEntry) => x.toInfo());
    return {
      provider: {
        id: p.id, name: p.name, format: p.format, baseUrl: p.baseUrl, apiKey: SecretStore.get(SECRET_PREFIX + p.id),
        headers: p.headerMap(), models: models
      },
      model: m.toInfo()
    };
  }

  /** Temperature for requests: NaN means "model default". */
  requestTemperature(): number {
    return this.temperature < 0 ? NaN : this.temperature;
  }

  /** Keeps the selection pointing at an existing model (first one if the old one is gone). */
  private fixSelection(): void {
    const all = this.choices();
    if (all.some((c: ModelChoice) => c.providerId === this.providerId && c.modelId === this.modelId)) {
      return;
    }
    this.providerId = all.length > 0 ? all[0].providerId : '';
    this.modelId = all.length > 0 ? all[0].modelId : '';
  }
}

export const agentSettings: AgentSettingsStore = new AgentSettingsStore();
