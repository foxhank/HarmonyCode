import { ApiFormat, ModelInfo } from './ProviderConfig';

/** A starting point for adding a provider; the user can change every field afterwards. */
export interface ProviderPreset {
  /** Stable id of the preset (also the default provider id). */
  id: string;
  name: string;
  format: string;
  baseUrl: string;
  models: ModelInfo[];
  /** The provider needs no API key (local servers). */
  keyless: boolean;
}

function m(id: string, contextWindow: number, reasoning: boolean): ModelInfo {
  return { id: id, name: '', contextWindow: contextWindow, maxOutputTokens: 0, reasoning: reasoning };
}

/** Well-known endpoints offered when adding a provider. */
export class ProviderPresets {
  static readonly CUSTOM_ID: string = 'custom';

  static all(): ProviderPreset[] {
    return [
      {
        id: 'openai', name: 'OpenAI', format: ApiFormat.OPENAI_RESPONSES, baseUrl: 'https://api.openai.com/v1',
        models: [m('gpt-5', 400000, true), m('gpt-5-mini', 400000, true), m('gpt-4.1', 1000000, false)], keyless: false
      },
      {
        id: 'anthropic', name: 'Anthropic', format: ApiFormat.ANTHROPIC, baseUrl: 'https://api.anthropic.com',
        models: [m('claude-opus-5-5', 200000, false), m('claude-sonnet-5-5', 200000, false),
          m('claude-haiku-5-5', 200000, false)], keyless: false
      },
      {
        id: 'deepseek', name: 'DeepSeek', format: ApiFormat.OPENAI_CHAT, baseUrl: 'https://api.deepseek.com',
        models: [m('deepseek-chat', 128000, false), m('deepseek-reasoner', 128000, false)], keyless: false
      },
      {
        id: 'openrouter', name: 'OpenRouter', format: ApiFormat.OPENAI_CHAT, baseUrl: 'https://openrouter.ai/api/v1',
        models: [], keyless: false
      },
      {
        id: 'ollama', name: 'Ollama', format: ApiFormat.OPENAI_CHAT, baseUrl: 'http://127.0.0.1:11434/v1',
        models: [], keyless: true
      },
      {
        id: ProviderPresets.CUSTOM_ID, name: '', format: ApiFormat.OPENAI_CHAT, baseUrl: '', models: [], keyless: false
      }
    ];
  }

  static get(id: string): ProviderPreset | undefined {
    return ProviderPresets.all().find((p: ProviderPreset) => p.id === id);
  }
}
