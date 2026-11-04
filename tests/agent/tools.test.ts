// Offline tests of the agent's tools and loop features: multi_edit, move_path, full-access paths,
// command approval rules, background jobs, ask_user, HTML-to-text, parallel reads, messages sent
// mid-turn (steering) and sub-agents (with a scripted model).
// Usage: node build.mjs tools
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { AgentListener, ToolCallView } from '../../entry/src/main/ets/core/agent/AgentEvents';
import { AgentFs, FsEntry, FsStat } from '../../entry/src/main/ets/core/agent/AgentFs';
import { ApprovalMode, ApprovalPolicy } from '../../entry/src/main/ets/core/agent/Approval';
import { AgentSession } from '../../entry/src/main/ets/core/agent/AgentSession';
import { UserPrompter, UserQuestion } from '../../entry/src/main/ets/core/agent/Interaction';
import { PathGuard } from '../../entry/src/main/ets/core/agent/PathGuard';
import { ToolArgs, ToolContext, ToolKind, ToolOutput } from '../../entry/src/main/ets/core/agent/ToolTypes';
import { AskUserTool } from '../../entry/src/main/ets/core/agent/tools/AskUserTool';
import { CommandOutputTool, KillCommandTool } from '../../entry/src/main/ets/core/agent/tools/JobTools';
import { MovePathTool } from '../../entry/src/main/ets/core/agent/tools/MovePathTool';
import { MultiEditTool } from '../../entry/src/main/ets/core/agent/tools/MultiEditTool';
import { RunCommandTool } from '../../entry/src/main/ets/core/agent/tools/RunCommandTool';
import { HtmlText } from '../../entry/src/main/ets/core/agent/web/HtmlText';
import { ChatModel } from '../../entry/src/main/ets/core/llm/ChatModel';
import { HttpBodySink, HttpRequestSpec, HttpTransport } from '../../entry/src/main/ets/core/llm/HttpTransport';
import { LlmClient } from '../../entry/src/main/ets/core/llm/LlmClient';
import { TokenUsage } from '../../entry/src/main/ets/core/llm/LlmTypes';
import { ApiFormat, ModelInfo, ProviderConfig } from '../../entry/src/main/ets/core/llm/ProviderConfig';
import { NodeAgentFs } from './NodeAgentFs';
import { makeCtx, makeDeps } from './TestDeps';

let failures = 0;
function check(cond: boolean, what: string): void {
  console.log((cond ? '  PASS ' : '  FAIL ') + what);
  if (!cond) {
    failures++;
  }
}

const tmp = (): string => fs.mkdtempSync(path.join(os.tmpdir(), 'hc-tools-')).replace(/\\/g, '/');
const args = (o: object): ToolArgs => new ToolArgs(o as Record<string, Object>);

async function attempt(p: Promise<ToolOutput>): Promise<string> {
  try {
    return (await p).text;
  } catch (e) {
    return 'ERR ' + (e as Error).message;
  }
}

async function testEdits(): Promise<void> {
  console.log('\n== multi_edit and move_path');
  const root = tmp();
  const ctx = makeCtx(root);
  fs.writeFileSync(root + '/m.ts', 'const a = 1;\nconst b = 2;\nconst c = 3;\n');
  ctx.reads.record(root + '/m.ts', fs.readFileSync(root + '/m.ts', 'utf-8'));
  const me = new MultiEditTool();
  const bad = await attempt(me.run(args({ path: 'm.ts', edits: [
    { old_string: 'const a = 1;', new_string: 'const a = 10;' }, { old_string: 'nope', new_string: 'x' }] }), ctx));
  check(bad.includes('Edit 2 of 2 failed') && fs.readFileSync(root + '/m.ts', 'utf-8').includes('const a = 1;'),
    'failed multi_edit changes nothing');
  const ok = await attempt(me.run(args({ path: 'm.ts', edits: [
    { old_string: 'const a = 1;', new_string: 'const a = 10;' }, { old_string: 'const a = 10;\nconst b', new_string: 'let b' }] }), ctx));
  check(ok.includes('2 edits') && fs.readFileSync(root + '/m.ts', 'utf-8') === 'let b = 2;\nconst c = 3;\n',
    'edits apply in sequence');
  const mv = new MovePathTool();
  check((await attempt(mv.run(args({ from: 'm.ts', to: 'src/deep/n.ts' }), ctx))).startsWith('Moved') &&
    fs.existsSync(root + '/src/deep/n.ts') && !fs.existsSync(root + '/m.ts'), 'move creates parent folders');
  fs.writeFileSync(root + '/x.txt', 'x');
  check((await attempt(mv.run(args({ from: 'x.txt', to: 'src/deep/n.ts' }), ctx))).includes('already exists'), 'no silent overwrite');
  check((await attempt(mv.run(args({ from: 'src', to: 'src/inner' }), ctx))).includes('into itself'), 'no move into itself');
  check((await attempt(mv.run(args({ from: 'x.txt', to: '../out.txt' }), ctx))).includes('outside the project'), 'confined');
}

function testPaths(): void {
  console.log('\n== Paths');
  const g = new PathGuard('/home/dev/proj', false, '/home/dev');
  check(g.resolve('/etc/hosts') === '/etc/hosts' && g.resolve('../x') === '/home/dev/x', 'full access outside the root');
  check(g.resolve('~/notes.md') === '/home/dev/notes.md', '~ is the home folder');
  const w = new PathGuard('/C:/Users/dev', false);
  check(w.resolve('C:\\Windows\\System32') === '/C:/Windows/System32' && w.resolve('D:/data') === '/D:/data',
    'Windows drive paths in SFTP form');
  check(w.rel('/C:/Users/dev/a/b.txt') === 'a/b.txt' && w.rel('/D:/x') === '/D:/x', 'display paths');
}

function testRules(): void {
  console.log('\n== Approval rules');
  check(ApprovalPolicy.commandKey('npm test -- --watch') === 'npm test', 'npm test prefix');
  check(ApprovalPolicy.commandKey('git status') === 'git status' && ApprovalPolicy.commandKey('ls -la') === 'ls', 'git / plain');
  check(ApprovalPolicy.commandKey('npm test && rm -rf /') === '' && ApprovalPolicy.commandKey('echo $(whoami)') === '',
    'compound commands never match a rule');
  const p = new ApprovalPolicy(ApprovalMode.ASK);
  p.allowAlways(ToolKind.EXECUTE, 'npm test');
  check(!p.needsApproval(ToolKind.EXECUTE, 'npm test') && p.needsApproval(ToolKind.EXECUTE, 'npm publish'),
    'rule covers only its prefix');
  check(p.needsApproval(ToolKind.EXECUTE, ''), 'commands without a key still ask');
  check(p.needsApproval(ToolKind.NETWORK, '') && !new ApprovalPolicy(ApprovalMode.AUTO_EDIT).needsApproval(ToolKind.NETWORK, ''),
    'web fetch asks only in ask mode');
}

async function testJobs(): Promise<void> {
  console.log('\n== Background jobs');
  const root = tmp();
  const ctx = makeCtx(root);
  const run = new RunCommandTool();
  const started = await run.run(args({ command: 'echo begin; sleep 2; echo end', run_in_background: true }), ctx);
  check(started.text.includes('job1') && started.text.includes('begin'), 'starts and shows early output: ' + started.text.split('\n')[0]);
  const out = new CommandOutputTool();
  const later = await out.run(args({ job_id: 'job1', wait_ms: 5000 }), ctx);
  const after = later.text.includes('end') ? later : await out.run(args({ job_id: 'job1', wait_ms: 5000 }), ctx);
  check(after.text.includes('end'), 'command_output returns new output');
  const fin = await out.run(args({ job_id: 'job1', wait_ms: 3000 }), ctx);
  check(fin.text.includes('exited with code 0'), 'reports the exit: ' + fin.text.split('\n')[0]);
  await run.run(args({ command: 'sleep 30', run_in_background: true }), ctx);
  const t0 = Date.now();
  const killed = await new KillCommandTool().run(args({ job_id: 'job2' }), ctx);
  check(killed.text.startsWith('Stopped job job2') && Date.now() - t0 < 5000, 'kill_command stops a job');
  check((await out.run(args({}), ctx)).text.includes('stopped by kill_command'), 'job list shows states');
}

async function testAsk(): Promise<void> {
  console.log('\n== ask_user');
  const asked: UserQuestion[] = [];
  const ctx: ToolContext = makeCtx(tmp());
  ctx.prompter = { ask: async (q: UserQuestion) => (asked.push(q), 'Use PostgreSQL') };
  const r = await new AskUserTool().run(args({ question: 'Which database?', options: [
    { label: 'PostgreSQL', description: 'robust' }, { label: 'SQLite' }] }), ctx);
  check(asked.length === 1 && asked[0].options.length === 2 && r.text.includes('Use PostgreSQL'), 'question and answer');
  ctx.prompter = { ask: async () => '' };
  check((await new AskUserTool().run(args({ question: 'x?' }), ctx)).text.includes('dismissed'), 'dismissed question');
}

function testHtml(): void {
  console.log('\n== HTML to text');
  const html = '<html><head><title>Doc &amp; API</title><style>x{}</style></head><body><nav>menu</nav>' +
    '<h1>Install</h1><p>Run <code>npm i x</code> or see <a href="https://x.dev/docs">the docs</a>.</p>' +
    '<ul><li>one</li><li>two</li></ul><pre>  indented\n    code</pre><script>evil()</script></body></html>';
  const t = HtmlText.toText(html);
  check(HtmlText.title(html) === 'Doc & API', 'title');
  check(t.includes('# Install') && t.includes('`npm i x`') && t.includes('[the docs](https://x.dev/docs)'), 'headings, code, links');
  check(t.includes('- one') && t.includes('- two') && t.includes('  indented\n    code'), 'lists and preformatted text');
  check(!t.includes('evil') && !t.includes('menu'), 'scripts and navigation dropped');
}

/** A model that answers by script with OpenAI-style tool calls. */
type Reply = { text?: string; calls?: Array<{ name: string; args: object }> };

class ScriptedModel implements HttpTransport {
  requests: Array<{ system: string; messages: Array<{ role: string; content: string }> }> = [];
  private n = 0;

  constructor(private script: (req: { system: string; messages: Array<{ role: string; content: string }> }) => Reply) {}

  async send(spec: HttpRequestSpec, sink: HttpBodySink): Promise<number> {
    const body = JSON.parse(spec.body);
    const sys = body.messages[0]?.role === 'system' ? body.messages[0].content : '';
    const req = { system: sys, messages: body.messages };
    this.requests.push(req);
    const r = this.script(req);
    const ev = (delta: object, finish: string | null): string =>
      'data: ' + JSON.stringify({ choices: [{ index: 0, delta: delta, finish_reason: finish }] }) + '\n\n';
    let out = '';
    if (r.text) {
      out += ev({ content: r.text }, null);
    }
    (r.calls ?? []).forEach((c, i) => {
      this.n++;
      out += ev({ tool_calls: [{ index: i, id: 'call' + this.n, type: 'function', function: { name: c.name, arguments: JSON.stringify(c.args) } }] }, null);
    });
    out += ev({}, r.calls && r.calls.length > 0 ? 'tool_calls' : 'stop') + 'data: [DONE]\n\n';
    sink.onText(out);
    return 200;
  }
}

/** AgentFs whose reads take a while, to see whether they overlap. */
class SlowFs extends NodeAgentFs {
  active = 0;
  maxActive = 0;

  async readText(p: string): Promise<string> {
    this.active++;
    this.maxActive = Math.max(this.maxActive, this.active);
    await new Promise((res) => setTimeout(res, 300));
    this.active--;
    return super.readText(p);
  }
}

class Quiet implements AgentListener {
  calls: ToolCallView[] = [];
  outputs: Map<string, string> = new Map();
  status = '';
  live = '';
  onTurnStart(): void {}
  onStepStart(): void {}
  onTextDelta(): void {}
  onReasoningDelta(): void {}
  onToolCall(c: ToolCallView): void {
    this.calls.push(c);
  }
  onToolStatus(): void {}
  onToolOutput(id: string, o: ToolOutput): void {
    this.outputs.set(id, o.text);
  }
  onCommandOutput(id: string, chunk: string): void {
    this.live += chunk;
  }
  onPlan(): void {}
  onUsage(u: TokenUsage): void {}
  onNotice(): void {}
  onFilesChanged(): void {}
  onTurnEnd(s: string): void {
    this.status = s;
  }
}

const modelInfo: ModelInfo = { id: 'm', name: '', contextWindow: 100000, maxOutputTokens: 0, reasoning: false };
const provider: ProviderConfig = { id: 'p', name: 'P', format: ApiFormat.OPENAI_CHAT, baseUrl: 'http://x', apiKey: '', headers: {}, models: [modelInfo] };

async function testLoop(): Promise<void> {
  console.log('\n== Loop: parallel reads, steering, sub-agents');
  const root = tmp();
  fs.writeFileSync(root + '/a.txt', 'alpha');
  fs.writeFileSync(root + '/b.txt', 'beta');
  let session: AgentSession | null = null;
  const transport = new ScriptedModel((req) => {
    const last = req.messages[req.messages.length - 1];
    if (req.system.includes('research sub-agent')) {
      return last.role === 'user' && last.content.includes('Find where') ? { calls: [{ name: 'grep', args: { pattern: 'beta' } }] } :
        { text: 'REPORT: beta is in b.txt line 1' };
    }
    const n = req.messages.filter((m) => m.role === 'assistant').length;
    if (n === 0) {
      setTimeout(() => session?.steer('Also mention the word PINEAPPLE.'), 50);
      return { calls: [{ name: 'read_file', args: { path: 'a.txt' } }, { name: 'read_file', args: { path: 'b.txt' } }] };
    }
    if (n === 1) {
      return { calls: [{ name: 'task', args: { description: 'find beta', prompt: 'Find where beta is defined.' } }] };
    }
    return { text: 'done' };
  });
  const slow = new SlowFs();
  const deps = makeDeps(new ChatModel(new LlmClient(transport), provider, modelInfo), root, { mode: ApprovalMode.FULL_AUTO });
  deps.fs = slow;
  const rec = new Quiet();
  session = new AgentSession(deps, rec);
  const t0 = Date.now();
  await session.send('Read both files, then research.');
  check(rec.status === 'done', 'turn finished: ' + rec.status);
  check(slow.maxActive >= 2, 'the two reads overlapped (max concurrent ' + slow.maxActive + ')');
  const second = transport.requests.find((r) => r.messages.filter((m) => m.role === 'assistant').length === 1 &&
    !r.system.includes('research sub-agent'));
  const toolMsgs = second ? second.messages.filter((m) => m.role === 'tool') : [];
  check(toolMsgs.length === 2 && toolMsgs[0].content.includes('alpha') && toolMsgs[1].content.includes('beta'),
    'results come back in call order');
  const lastUser = second ? second.messages[second.messages.length - 1] : { role: '', content: '' };
  check(lastUser.role === 'user' && lastUser.content.includes('PINEAPPLE'), 'message sent mid-turn reached the model');
  const taskCall = rec.calls.find((c) => c.toolName === 'task');
  check(taskCall !== undefined && (rec.outputs.get(taskCall.callId) ?? '').includes('REPORT: beta is in b.txt'),
    'sub-agent report returned to the main agent');
  check(rec.live.includes('grep'), 'sub-agent progress streamed: ' + rec.live.trim());
  const subReq = transport.requests.find((r) => r.system.includes('research sub-agent'));
  check(subReq !== undefined && !JSON.stringify(subReq).includes('"edit_file"'), 'sub-agent prompt has its role');
  void t0;
}

async function main(): Promise<void> {
  await testEdits();
  testPaths();
  testRules();
  await testJobs();
  await testAsk();
  testHtml();
  await testLoop();
  console.log(failures === 0 ? '\nALL PASSED' : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e: Error) => {
  console.error(e);
  process.exit(1);
});
