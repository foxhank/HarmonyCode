import { ApiAdapter } from './ApiAdapter';
import { AnthropicAdapter } from './adapters/AnthropicAdapter';
import { OpenAiChatAdapter } from './adapters/OpenAiChatAdapter';
import { OpenAiResponsesAdapter } from './adapters/OpenAiResponsesAdapter';

/** Format id -> adapter. New wire formats are added here and nowhere else. */
export class AdapterRegistry {
  private adapters: Map<string, ApiAdapter> = new Map();

  register(adapter: ApiAdapter): AdapterRegistry {
    this.adapters.set(adapter.format, adapter);
    return this;
  }

  get(format: string): ApiAdapter | undefined {
    return this.adapters.get(format);
  }

  formats(): string[] {
    return Array.from(this.adapters.keys());
  }

  /** All built-in formats. */
  static standard(): AdapterRegistry {
    return new AdapterRegistry()
      .register(new OpenAiChatAdapter())
      .register(new OpenAiResponsesAdapter())
      .register(new AnthropicAdapter());
  }
}
