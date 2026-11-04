import { WebAccess } from '../../core/agent/web/WebAccess';
import { CancelToken } from '../../core/llm/CancelToken';
import { ChatModel } from '../../core/llm/ChatModel';
import { LlmClient } from '../../core/llm/LlmClient';
import { ChatMessage, LlmRequest } from '../../core/llm/LlmTypes';
import { ModelInfo, ProviderConfig } from '../../core/llm/ProviderConfig';
import { OhosHttpTransport } from '../../core/llm/transport/OhosHttpTransport';
import { agentSettings } from '../../core/settings/AgentSettingsStore';

const PROBE_MAX_TOKENS: number = 16;
const PROBE_TIMEOUT_MS: number = 30000;

/** The app's single model client and web client, plus a connection check for Settings. */
export class LlmServices {
  static readonly transport: OhosHttpTransport = new OhosHttpTransport();
  static readonly client: LlmClient = new LlmClient(LlmServices.transport);
  /** Web search and fetch for the agent, following the search settings as they change. */
  static readonly web: WebAccess = new WebAccess(LlmServices.transport, () => agentSettings.webSettings());

  static model(provider: ProviderConfig, model: ModelInfo): ChatModel {
    return new ChatModel(LlmServices.client, provider, model);
  }

  /** Sends a tiny request. Resolves with the model's reply; rejects with the provider's error. */
  static async probe(provider: ProviderConfig, model: ModelInfo): Promise<string> {
    const req = new LlmRequest();
    req.messages = [ChatMessage.user('Reply with the single word OK.')];
    req.maxOutputTokens = PROBE_MAX_TOKENS;
    const cancel = new CancelToken();
    const timer = setTimeout(() => cancel.cancel(), PROBE_TIMEOUT_MS);
    try {
      const r = await LlmServices.client.complete(provider, model, req, null, cancel);
      return r.message.textContent().trim();
    } finally {
      clearTimeout(timer);
    }
  }
}
