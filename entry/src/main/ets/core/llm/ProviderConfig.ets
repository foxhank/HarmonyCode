/** Wire formats the model layer can speak. Each has an ApiAdapter. */
export class ApiFormat {
  static readonly OPENAI_CHAT: string = 'openai-chat';
  static readonly OPENAI_RESPONSES: string = 'openai-responses';
  static readonly ANTHROPIC: string = 'anthropic';

  static all(): string[] {
    return [ApiFormat.OPENAI_CHAT, ApiFormat.OPENAI_RESPONSES, ApiFormat.ANTHROPIC];
  }
}

/** A model offered by a provider. */
export interface ModelInfo {
  /** Model id sent to the API, e.g. "gpt-5" or "claude-sonnet-4-5". */
  id: string;
  /** Name shown in the UI ('' = use the id). */
  name: string;
  /** Tokens the model accepts in total; used to decide when to compact the conversation. */
  contextWindow: number;
  /** Cap on output tokens per call; 0 = provider default. */
  maxOutputTokens: number;
  /** The model produces reasoning that must be carried between calls (OpenAI Responses: encrypted). */
  reasoning: boolean;
}

/** A model provider endpoint, built in or added by the user. */
export interface ProviderConfig {
  id: string;
  name: string;
  format: string;
  /** e.g. https://api.openai.com/v1, https://api.anthropic.com, https://api.deepseek.com */
  baseUrl: string;
  /** Resolved secret; never written to preferences (see AgentSettingsStore). */
  apiKey: string;
  /** Extra HTTP headers sent with every request. */
  headers: Record<string, string>;
  models: ModelInfo[];
}

export class ModelDefaults {
  static readonly CONTEXT_WINDOW: number = 128000;
}

/** Display name of a model. */
export function modelLabel(m: ModelInfo): string {
  return m.name.length > 0 ? m.name : m.id;
}

/** Joins a base URL and a path, accepting bases that already end with that path or with '/'. */
export function endpointUrl(baseUrl: string, path: string): string {
  let base = baseUrl.trim();
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  if (base.endsWith(path)) {
    return base;
  }
  return base + path;
}
