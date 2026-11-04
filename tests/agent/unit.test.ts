// Offline tests: the OpenAI Responses adapter (request shape + stream decoding, via a replaying
// transport), SSE parsing across chunk boundaries, glob, diff, edit safety and context compaction.
// Usage: node build.mjs unit
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { AgentListener } from '../../entry/src/main/ets/core/agent/AgentEvents';
import { ApprovalDecision, ApprovalMode, ApprovalPolicy } from '../../entry/src/main/ets/core/agent/Approval';
import { AgentSession } from '../../entry/src/main/ets/core/agent/AgentSession';
import { ReadTracker } from '../../entry/src/main/ets/core/agent/ReadTracker';
import { ToolRegistry } from '../../entry/src/main/ets/core/agent/ToolRegistry';
import { ToolArgs, ToolContext, ToolOutput } from '../../entry/src/main/ets/core/agent/ToolTypes';
import { EditFileTool } from '../../entry/src/main/ets/core/agent/tools/EditFileTool';
import { GlobPattern } from '../../entry/src/main/ets/core/agent/util/GlobPattern';
import { LineDiff } from '../../entry/src/main/ets/core/agent/util/LineDiff';
import { CancelToken } from '../../entry/src/main/ets/core/llm/CancelToken';
import { ChatModel } from '../../entry/src/main/ets/core/llm/ChatModel';
import { HttpBodySink, HttpRequestSpec, HttpTransport } from '../../entry/src/main/ets/core/llm/HttpTransport';
import { LlmClient } from '../../entry/src/main/ets/core/llm/LlmClient';
import { ChatMessage, LlmRequest, MessagePart, Role, TokenUsage } from '../../entry/src/main/ets/core/llm/LlmTypes';
import { ApiFormat, ModelInfo, ProviderConfig } from '../../entry/src/main/ets/core/llm/ProviderConfig';
import { SseParser } from '../../entry/src/main/ets/core/llm/SseParser';
import { NodeAgentFs, NodeCommandRunner } from './NodeAgentFs';
import { makeCtx, makeDeps } from './TestDeps';

let failures = 0;

function check(cond: boolean, what: string): void {
  console.log((cond ? '  PASS ' : '  FAIL ') + what);
  if (!cond) {
    failures++;
  }
}

/** Replays canned responses and records the requests, splitting bodies into odd-sized chunks. */
class ReplayTransport implements HttpTransport {
  requests: HttpRequestSpec[] = [];
  private replies: Array<[number, string]>;

  constructor(replies: Array<[number, string]>) {
    this.replies = replies;
  }

  async send(spec: HttpRequestSpec, sink: HttpBodySink, cancel: CancelToken): Promise<number> {
    this.requests.push(spec);
    const r = this.replies.shift();
    if (r === undefined) {
      throw new Error('no more replies');
    }
    for (let i = 0; i < r[1].length; i += 7) {
      sink.onText(r[1].substring(i, i + 7));
    }
    return r[0];
  }
}

function sse(events: object[]): string {
  return events.map((e) => `event: ${(e as { type: string }).type}\r\ndata: ${JSON.stringify(e)}\r\n\r\n`).join('');
}

const model: ModelInfo = { id: 'gpt-test', name: '', contextWindow: 128000, maxOutputTokens: 4096, reasoning: true };
const responses: ProviderConfig = {
  id: 'openai', name: 'OpenAI', format: ApiFormat.OPENAI_RESPONSES, baseUrl: 'https://api.openai.com/v1/',
  apiKey: 'sk-test', headers: { 'X-Extra': '1' }, models: [model]
};

async function testResponses(): Promise<void> {
  console.log('\n== OpenAI Responses adapter');
  const turn1 = sse([
    { type: 'response.created', response: { id: 'r1' } },
    { type: 'response.output_item.added', output_index: 0, item: { type: 'reasoning', id: 'rs_1' } },
    { type: 'response.reasoning_summary_text.delta', output_index: 0, item_id: 'rs_1', delta: 'Need the weather.' },
    { type: 'response.output_item.done', output_index: 0, item: { type: 'reasoning', id: 'rs_1', encrypted_content: 'ENC123', summary: [{ type: 'summary_text', text: 'Need the weather.' }] } },
    { type: 'response.output_item.added', output_index: 1, item: { type: 'message', id: 'msg_1' } },
    { type: 'response.output_text.delta', output_index: 1, item_id: 'msg_1', delta: 'Checking ' },
    { type: 'response.output_text.delta', output_index: 1, item_id: 'msg_1', delta: 'now.' },
    { type: 'response.output_item.added', output_index: 2, item: { type: 'function_call', id: 'fc_1', call_id: 'call_A', name: 'get_weather', arguments: '' } },
    { type: 'response.function_call_arguments.delta', item_id: 'fc_1', delta: '{"city":' },
    { type: 'response.function_call_arguments.delta', item_id: 'fc_1', delta: '"Oslo"}' },
    { type: 'response.output_item.done', output_index: 2, item: { type: 'function_call', id: 'fc_1', call_id: 'call_A', name: 'get_weather', arguments: '{"city":"Oslo"}' } },
    { type: 'response.completed', response: { status: 'completed', usage: { input_tokens: 50, output_tokens: 20, input_tokens_details: { cached_tokens: 10 } } } }
  ]);
  const turn2 = sse([
    { type: 'response.output_item.added', output_index: 0, item: { type: 'message', id: 'msg_2' } },
    { type: 'response.output_text.delta', output_index: 0, item_id: 'msg_2', delta: 'Oslo: 5 C.' },
    { type: 'response.completed', response: { status: 'completed', usage: { input_tokens: 80, output_tokens: 5 } } }
  ]);
  const t = new ReplayTransport([[200, turn1], [200, turn2]]);
  const client = new LlmClient(t);
  const req = new LlmRequest();
  req.system = 'sys';
  req.messages = [ChatMessage.user('Weather in Oslo?')];
  req.tools = [{ name: 'get_weather', description: 'd', parameters: { 'type': 'object', 'properties': {} } }];
  let streamed = '';
  const r1 = await client.complete(responses, model, req, {
    onTextDelta: (s: string) => {
      streamed += s;
    }, onReasoningDelta: () => {
    }, onToolCallStart: () => {
    }
  }, new CancelToken());
  const spec = t.requests[0];
  const body = JSON.parse(spec.body);
  check(spec.url === 'https://api.openai.com/v1/responses', 'endpoint url: ' + spec.url);
  check(spec.headers['Authorization'] === 'Bearer sk-test' && spec.headers['X-Extra'] === '1', 'auth and extra headers');
  check(body.instructions === 'sys' && body.store === false && body.stream === true, 'instructions, stateless, streaming');
  check(body.tools[0].type === 'function' && body.tools[0].name === 'get_weather', 'flat function tool format');
  check(body.include[0] === 'reasoning.encrypted_content' && body.max_output_tokens === 4096, 'reasoning include + max tokens');
  check(body.input[0].role === 'user' && body.input[0].content[0].type === 'input_text', 'user input item');
  check(streamed === 'Checking now.' && r1.message.textContent() === 'Checking now.', 'text deltas assembled');
  const calls = r1.message.toolCalls();
  check(calls.length === 1 && calls[0].callId === 'call_A' && calls[0].argumentsJson === '{"city":"Oslo"}', 'function call assembled');
  check(r1.stopReason === 'tool_calls', 'stop reason tool_calls');
  check(r1.usage.inputTokens === 50 && r1.usage.cachedTokens === 10, 'usage with cached tokens');
  const reasoning = r1.message.parts.find((p) => p.kind === 'reasoning');
  check(reasoning !== undefined && reasoning.signature === 'ENC123' && reasoning.callId === 'rs_1', 'encrypted reasoning kept');

  req.messages.push(r1.message, new ChatMessage(Role.USER, [MessagePart.toolResult('call_A', '5 C', false)]));
  const r2 = await client.complete(responses, model, req, null, new CancelToken());
  const input2 = JSON.parse(t.requests[1].body).input;
  const types = input2.map((i: { type?: string; role?: string }) => i.type ?? i.role).join(',');
  check(types === 'user,reasoning,assistant,function_call,function_call_output', 'replayed items in order: ' + types);
  check(input2[1].encrypted_content === 'ENC123', 'reasoning echoed with encrypted content');
  check(input2[4].call_id === 'call_A' && input2[4].output === '5 C', 'function_call_output carries the result');
  check(r2.message.textContent() === 'Oslo: 5 C.' && r2.stopReason === 'end', 'final answer');

  // Errors and retries: a 500 is retried, then a 400 is reported without retry.
  const t2 = new ReplayTransport([[500, '{"error":{"message":"overloaded"}}'], [400, '{"error":{"type":"invalid_request_error","message":"bad tool"}}']]);
  try {
    await new LlmClient(t2).complete(responses, model, req, null, new CancelToken());
    check(false, 'error raised');
  } catch (e) {
    check(t2.requests.length === 2 && (e as Error).message === 'HTTP 400 — invalid_request_error: bad tool',
      'retried 5xx, reported 4xx: ' + (e as Error).message);
  }
  // A server that ignores stream:true and returns plain JSON.
  const plain = JSON.stringify({ output: [{ type: 'message', content: [{ type: 'output_text', text: 'plain' }] }], status: 'completed' });
  const r3 = await new LlmClient(new ReplayTransport([[200, plain]])).complete(responses, model, req, null, new CancelToken());
  check(r3.message.textContent() === 'plain', 'non-streamed body decoded');
}

function testSse(): void {
  console.log('\n== SSE parser');
  const got: string[] = [];
  const p = new SseParser((e: string, d: string) => got.push(e + '|' + d));
  const text = ': comment\r\nevent: a\r\ndata: 1\r\ndata: 2\r\n\r\ndata: x\n\ndata: tail';
  for (const ch of text) {
    p.feed(ch);
  }
  p.end();
  check(JSON.stringify(got) === JSON.stringify(['a|1\n2', '|x', '|tail']), 'events across 1-char chunks: ' + JSON.stringify(got));
}

function testGlobDiff(): void {
  console.log('\n== Glob and diff');
  check(new GlobPattern('*.ts').matches('src/a/b.ts') && !new GlobPattern('*.ts').matches('src/a/b.tsx'), 'basename glob');
  check(new GlobPattern('src/**/*.{ts,ets}').matches('src/x.ets') && new GlobPattern('src/**/*.{ts,ets}').matches('src/a/b/c.ts'), '** and {a,b}');
  check(!new GlobPattern('src/*.ts').matches('src/a/b.ts'), '* stays within a folder');
  const d = LineDiff.unified('f.txt', 'a\nb\nc\nd\n', 'a\nB\nc\nd\ne\n');
  check(d.includes('@@ -1,4 +1,5 @@') && d.includes('-b') && d.includes('+B') && d.includes('+e'), 'unified diff:\n' + d);
  const s = LineDiff.stats('a\nb\n', 'a\nc\nd\n');
  check(s.added === 2 && s.removed === 1, 'diff stats');
}

async function testEditSafety(): Promise<void> {
  console.log('\n== Edit safety');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hc-unit-')).replace(/\\/g, '/');
  fs.writeFileSync(root + '/a.py', 'x = 1\nx = 1\ny = 2\r\n');
  const ctx: ToolContext = makeCtx(root);
  const edit = new EditFileTool();
  const run = async (o: object): Promise<string> => {
    try {
      return (await edit.run(new ToolArgs(o as Record<string, Object>), ctx)).text;
    } catch (e) {
      return 'ERR ' + (e as Error).message;
    }
  };
  check((await run({ path: 'a.py', old_string: 'y = 2', new_string: 'y = 3' })).startsWith('ERR Read a.py'), 'edit refused before reading');
  ctx.reads.record(root + '/a.py', fs.readFileSync(root + '/a.py', 'utf-8'));
  check((await run({ path: 'a.py', old_string: 'x = 1', new_string: 'x = 2' })).includes('occurs 2 times'), 'ambiguous edit refused');
  check((await run({ path: 'a.py', old_string: 'x = 1', new_string: 'x = 2', replace_all: true })).includes('2 replacements'), 'replace_all');
  check((await run({ path: '../evil.py', old_string: 'a', new_string: 'b' })).includes('outside the project'), 'path escape blocked');
  fs.writeFileSync(root + '/a.py', 'changed by user\n');
  check((await run({ path: 'a.py', old_string: 'changed', new_string: 'x' })).includes('changed on disk'), 'stale read detected');
}

/** Model stub: answers by script and records each request. */
class ScriptedTransport implements HttpTransport {
  bodies: string[] = [];
  private next: (body: { messages: Array<{ role: string; content: string }> }) => string;

  constructor(next: (body: { messages: Array<{ role: string; content: string }> }) => string) {
    this.next = next;
  }

  async send(spec: HttpRequestSpec, sink: HttpBodySink): Promise<number> {
    this.bodies.push(spec.body);
    const chunk = (delta: object, finish: string | null, usage?: object): string =>
      'data: ' + JSON.stringify({ choices: [{ index: 0, delta: delta, finish_reason: finish }], usage: usage }) + '\n\n';
    const text = this.next(JSON.parse(spec.body));
    sink.onText(chunk({ content: text }, 'stop', { prompt_tokens: 0, completion_tokens: 1 }) + 'data: [DONE]\n\n');
    return 200;
  }
}

async function testCompaction(): Promise<void> {
  console.log('\n== Context compaction');
  const transport = new ScriptedTransport((b) => {
    const last = b.messages[b.messages.length - 1].content;
    return last.includes('handoff summary') ? 'SUMMARY: user is chatting about numbers.' : 'ok ' + b.messages.length;
  });
  const small: ModelInfo = { id: 'm', name: '', contextWindow: 3000, maxOutputTokens: 0, reasoning: false };
  const provider: ProviderConfig = { id: 'p', name: 'P', format: ApiFormat.OPENAI_CHAT, baseUrl: 'http://x', apiKey: '', headers: {}, models: [small] };
  const notices: string[] = [];
  const listener: AgentListener = {
    onTurnStart: () => {}, onStepStart: () => {}, onTextDelta: () => {}, onReasoningDelta: () => {},
    onToolCall: () => {}, onToolStatus: () => {}, onToolOutput: (id: string, o: ToolOutput) => {}, onCommandOutput: () => {},
    onPlan: () => {}, onUsage: (u: TokenUsage) => {}, onNotice: (k: string) => notices.push(k), onFilesChanged: () => {},
    onTurnEnd: () => {}
  };
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hc-compact-')).replace(/\\/g, '/');
  const s = new AgentSession(makeDeps(new ChatModel(new LlmClient(transport), provider, small), root,
    { mode: ApprovalMode.FULL_AUTO, maxSteps: 5 }), listener);
  for (let i = 0; i < 6; i++) {
    await s.send('Message ' + i + ': ' + 'lorem ipsum '.repeat(150));
  }
  check(notices.includes('compacted'), 'conversation was compacted when it outgrew the window');
  const hist = s.messages();
  check(hist[0].textContent().includes('SUMMARY: user is chatting about numbers.'), 'history now starts with the summary');
  check(hist.length < 12, 'history shrank (' + hist.length + ' messages)');
}

async function main(): Promise<void> {
  await testResponses();
  testSse();
  testGlobDiff();
  await testEditSafety();
  await testCompaction();
  console.log(failures === 0 ? '\nALL PASSED' : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e: Error) => {
  console.error(e);
  process.exit(1);
});
