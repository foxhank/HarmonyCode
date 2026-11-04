import { CancelToken } from './CancelToken';
import { LlmClient } from './LlmClient';
import { LlmRequest, LlmResult, LlmStreamListener } from './LlmTypes';
import { ModelInfo, modelLabel, ProviderConfig } from './ProviderConfig';

/**
 * A model bound to its provider: what agent code holds. It never sees URLs, keys or wire
 * formats — only provider-neutral requests and results.
 */
export class ChatModel {
  readonly provider: ProviderConfig;
  readonly model: ModelInfo;
  private client: LlmClient;

  constructor(client: LlmClient, provider: ProviderConfig, model: ModelInfo) {
    this.client = client;
    this.provider = provider;
    this.model = model;
  }

  get contextWindow(): number {
    return this.model.contextWindow;
  }

  /** "Provider · Model" for display. */
  label(): string {
    return this.provider.name + ' · ' + modelLabel(this.model);
  }

  complete(request: LlmRequest, listener: LlmStreamListener | null, cancel: CancelToken): Promise<LlmResult> {
    return this.client.complete(this.provider, this.model, request, listener, cancel);
  }
}
