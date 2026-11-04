// Live test of the model layer against a real provider: plain text, streaming, tool calls,
// a tool-result round trip, cancellation and error reporting, for every format the account offers.
// Usage: node build.mjs llm <account-file>
import { CancelToken } from '../../entry/src/main/ets/core/llm/CancelToken';
import { LlmClient } from '../../entry/src/main/ets/core/llm/LlmClient';
import { ChatMessage, LlmRequest, LlmStreamListener, MessagePart, Role, ToolSpec }
  from '../../entry/src/main/ets/core/llm/LlmTypes';
import { ApiFormat, ModelInfo, ProviderConfig } from '../../entry/src/main/ets/core/llm/ProviderConfig';
import { NodeHttpTransport } from './NodeHttpTransport';
import { readTestAccount } from './TestAccount';

const acct = readTestAccount(process.argv[2]);
const client = new LlmClient(new NodeHttpTransport());
const model: ModelInfo = { id: acct.model, name: '', contextWindow: 128000, maxOutputTokens: 0, reasoning: false };
const weather: ToolSpec = {
  name: 'get_weather',
  description: 'Current weather for a city.',
  parameters: { 'type': 'object', 'properties': { 'city': { 'type': 'string' } }, 'required': ['city'] }
};

function provider(format: string, baseUrl: string): ProviderConfig {
  return { id: format, name: 'DeepSeek', format: format, baseUrl: baseUrl, apiKey: acct.key, headers: {}, models: [model] };
}

let failures = 0;

function check(cond: boolean, what: string): void {
  console.log((cond ? '  PASS ' : '  FAIL ') + what);
  if (!cond) {
    failures++;
  }
}

async function run(p: ProviderConfig): Promise<void> {
  console.log(`\n== ${p.format} @ ${p.baseUrl}`);
  let streamed = '';
  const listener: LlmStreamListener = {
    onTextDelta: (t: string) => {
      streamed += t;
    },
    onReasoningDelta: () => {
    },
    onToolCallStart: () => {
    }
  };
  const r1 = new LlmRequest();
  r1.system = 'Answer in one short sentence.';
  r1.messages = [ChatMessage.user('Say hello and name the capital of France.')];
  const a = await client.complete(p, model, r1, listener, new CancelToken());
  check(a.message.textContent().toLowerCase().includes('paris'),
    'plain answer mentions Paris: ' + JSON.stringify(a.message.textContent()));
  check(streamed === a.message.textContent(), 'streamed deltas equal the final text');
  check(a.usage.inputTokens > 0 && a.usage.outputTokens > 0,
    `usage reported (${a.usage.inputTokens} in / ${a.usage.outputTokens} out)`);

  const r2 = new LlmRequest();
  r2.messages = [ChatMessage.user('What is the weather in Tokyo? Use the tool.')];
  r2.tools = [weather];
  const b = await client.complete(p, model, r2, null, new CancelToken());
  const calls = b.message.toolCalls();
  check(b.stopReason === 'tool_calls' && calls.length >= 1 && calls[0].toolName === 'get_weather',
    'model called get_weather, stop=' + b.stopReason);
  check(calls.length > 0 && String(JSON.parse(calls[0].argumentsJson).city).toLowerCase().includes('tokyo'),
    'arguments: ' + (calls.length > 0 ? calls[0].argumentsJson : ''));

  const results = calls.map((c: MessagePart) => MessagePart.toolResult(c.callId, '{"temp_c": 21, "sky": "clear"}', false));
  r2.messages.push(b.message, new ChatMessage(Role.USER, results));
  const c = await client.complete(p, model, r2, null, new CancelToken());
  check(c.message.textContent().includes('21'), 'answer uses the tool result: ' + JSON.stringify(c.message.textContent()));

  const cancel = new CancelToken();
  const r3 = new LlmRequest();
  r3.messages = [ChatMessage.user('Count from 1 to 300, one number per line.')];
  setTimeout(() => cancel.cancel(), 1500);
  try {
    await client.complete(p, model, r3, null, cancel);
    check(false, 'cancel stops the call');
  } catch (e) {
    check((e as Error).name === 'CancelledError', 'cancel stops the call');
  }
}

async function main(): Promise<void> {
  await run(provider(ApiFormat.OPENAI_CHAT, acct.openaiBase));
  if (acct.anthropicBase) {
    await run(provider(ApiFormat.ANTHROPIC, acct.anthropicBase));
  }
  // A bad key must produce a readable error, without retrying.
  try {
    const bad = provider(ApiFormat.OPENAI_CHAT, acct.openaiBase);
    bad.apiKey = 'sk-invalid';
    const r = new LlmRequest();
    r.messages = [ChatMessage.user('hi')];
    await client.complete(bad, model, r, null, new CancelToken());
    check(false, 'bad key rejected');
  } catch (e) {
    check((e as Error).message.startsWith('HTTP 401'), 'bad key rejected: ' + (e as Error).message);
  }
  console.log(failures === 0 ? '\nALL PASSED' : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e: Error) => {
  console.error(e);
  process.exit(1);
});
