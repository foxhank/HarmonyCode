// End-to-end test of the ReAct agent with a live model: it must find and fix a bug, verify the fix by
// running the tests, keep a plan, and respect approvals (a denied command must not run).
// Usage: node build.mjs agent <account-file> [openai-chat|anthropic]
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { AgentListener, ToolCallView } from '../../entry/src/main/ets/core/agent/AgentEvents';
import { ApprovalDecision, ApprovalGate, ApprovalMode, ApprovalPolicy, ApprovalReply, ApprovalRequest }
  from '../../entry/src/main/ets/core/agent/Approval';
import { AgentSession } from '../../entry/src/main/ets/core/agent/AgentSession';
import { PlanStep } from '../../entry/src/main/ets/core/agent/PlanTypes';
import { ToolRegistry } from '../../entry/src/main/ets/core/agent/ToolRegistry';
import { ToolOutput } from '../../entry/src/main/ets/core/agent/ToolTypes';
import { CancelToken } from '../../entry/src/main/ets/core/llm/CancelToken';
import { ChatModel } from '../../entry/src/main/ets/core/llm/ChatModel';
import { LlmClient } from '../../entry/src/main/ets/core/llm/LlmClient';
import { TokenUsage } from '../../entry/src/main/ets/core/llm/LlmTypes';
import { ApiFormat, ModelInfo, ProviderConfig } from '../../entry/src/main/ets/core/llm/ProviderConfig';
import { NodeAgentFs, NodeCommandRunner } from './NodeAgentFs';
import { makeDeps } from './TestDeps';
import { NodeHttpTransport } from './NodeHttpTransport';
import { readTestAccount } from './TestAccount';

const acct = readTestAccount(process.argv[2]);
const format = process.argv[3] ?? ApiFormat.OPENAI_CHAT;
const model: ModelInfo = { id: acct.model, name: '', contextWindow: 128000, maxOutputTokens: 0, reasoning: false };
const provider: ProviderConfig = {
  id: 'deepseek', name: 'DeepSeek', format: format,
  baseUrl: format === ApiFormat.ANTHROPIC ? acct.anthropicBase : acct.openaiBase,
  apiKey: acct.key, headers: {}, models: [model]
};

let failures = 0;

function check(cond: boolean, what: string): void {
  console.log((cond ? '  PASS ' : '  FAIL ') + what);
  if (!cond) {
    failures++;
  }
}

/** Prints the transcript and records what happened. */
class Recorder implements AgentListener {
  tools: string[] = [];
  statuses: Map<string, string> = new Map();
  plans: number = 0;
  text: string = '';
  endStatus: string = '';
  endError: string = '';
  changed: string[] = [];

  onTurnStart(): void {
  }

  onStepStart(step: number): void {
    process.stdout.write(`\n  [step ${step}] `);
  }

  onTextDelta(t: string): void {
    this.text += t;
    process.stdout.write(t);
  }

  onReasoningDelta(): void {
  }

  onToolCall(c: ToolCallView): void {
    this.tools.push(c.toolName);
    process.stdout.write(`\n    -> ${c.toolName} ${c.argumentsJson.substring(0, 140).replace(/\n/g, '\\n')}`);
  }

  onToolStatus(id: string, s: string): void {
    this.statuses.set(id, s);
  }

  onToolOutput(id: string, o: ToolOutput): void {
    process.stdout.write(`\n       ${o.isError ? 'ERR' : 'ok '} ${o.text.substring(0, 160).replace(/\n/g, ' | ')}`);
  }

  onCommandOutput(): void {
  }

  onPlan(steps: PlanStep[]): void {
    this.plans++;
    process.stdout.write('\n    plan: ' + steps.map((s) => `[${s.status}] ${s.step}`).join('; '));
  }

  onUsage(u: TokenUsage, ctx: number, win: number): void {
    process.stdout.write(`  (ctx ${ctx}/${win})`);
  }

  onNotice(kind: string): void {
    process.stdout.write(`\n    notice: ${kind}`);
  }

  onFilesChanged(paths: string[]): void {
    this.changed.push(...paths);
  }

  onTurnEnd(status: string, error: string): void {
    this.endStatus = status;
    this.endError = error;
    console.log(`\n  [turn end: ${status}${error ? ' — ' + error : ''}]`);
  }
}

class ScriptedGate implements ApprovalGate {
  asked: ApprovalRequest[] = [];
  private decide: (r: ApprovalRequest) => ApprovalReply;

  constructor(decide: (r: ApprovalRequest) => ApprovalReply) {
    this.decide = decide;
  }

  async request(r: ApprovalRequest): Promise<ApprovalReply> {
    this.asked.push(r);
    return this.decide(r);
  }
}

function makeProject(): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hc-agent-')).replace(/\\/g, '/');
  fs.writeFileSync(root + '/stats.js', [
    '// Small statistics helpers.',
    'function mean(xs) {',
    '  let total = 0;',
    '  for (let i = 1; i < xs.length; i++) {',
    '    total += xs[i];',
    '  }',
    '  return total / xs.length;',
    '}',
    '',
    'function median(xs) {',
    '  const s = [...xs].sort();',
    '  const mid = Math.floor(s.length / 2);',
    '  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;',
    '}',
    '',
    'module.exports = { mean, median };',
    ''
  ].join('\n'));
  fs.writeFileSync(root + '/test.js', [
    'const assert = require("assert");',
    'const { mean, median } = require("./stats");',
    'assert.strictEqual(mean([2, 4, 6]), 4);',
    'assert.strictEqual(median([10, 9, 100]), 10);',
    'assert.strictEqual(median([1, 2, 3, 4]), 2.5);',
    'console.log("all tests passed");',
    ''
  ].join('\n'));
  fs.writeFileSync(root + '/README.md', '# stats\nRun the tests with `node test.js`.\n');
  return root;
}

function session(root: string, mode: string, gate: ApprovalGate, rec: Recorder): AgentSession {
  return new AgentSession(makeDeps(new ChatModel(new LlmClient(new NodeHttpTransport()), provider, model), root,
    { mode: mode, gate: gate, name: 'stats' }), rec);
}

async function fixBug(): Promise<void> {
  console.log(`\n== Scenario 1 (${format}): fix the failing tests, edits auto-approved, commands approved by the user`);
  const root = makeProject();
  const rec = new Recorder();
  const gate = new ScriptedGate(() => ({ decision: ApprovalDecision.APPROVE, feedback: '' }));
  const s = session(root, ApprovalMode.AUTO_EDIT, gate, rec);
  await s.send('The tests in this project fail. Find the bugs, fix them, and make sure `node test.js` passes. ' +
    'Keep a plan while you work.');
  check(rec.endStatus === 'done', 'turn finished normally');
  check(rec.tools.includes('read_file'), 'agent read files');
  check(['edit_file', 'multi_edit', 'write_file'].some((t) => rec.tools.includes(t)), 'agent edited code');
  check(rec.tools.includes('run_command'), 'agent ran a command');
  check(gate.asked.length > 0 && gate.asked.every((a) => a.kind === 'execute'), `only commands asked for approval (${gate.asked.length})`);
  check(rec.changed.some((p) => p.endsWith('stats.js')), 'IDE was told stats.js changed');
  const r = await new NodeCommandRunner().run('node test.js', root, 30000, new CancelToken(), () => {});
  check(r.exitCode === 0, 'node test.js passes after the agent: ' + r.output.trim());
  check(rec.plans > 0, 'agent kept a plan');

  console.log('\n== Scenario 2: follow-up in the same conversation uses earlier context');
  await s.send('In one sentence: which two bugs did you fix?');
  check(rec.endStatus === 'done' && /sort|median/i.test(rec.text) && /mean|index|loop|0/i.test(rec.text),
    'answer refers to the earlier fixes');
}

async function denial(): Promise<void> {
  console.log(`\n== Scenario 3 (${format}): ask mode, the user denies the command`);
  const root = makeProject();
  const rec = new Recorder();
  const gate = new ScriptedGate((r) => ({ decision: ApprovalDecision.DENY, feedback: '' }));
  const s = session(root, ApprovalMode.ASK, gate, rec);
  await s.send('Run `node test.js > ran.txt` and tell me the result. Do not change any files.');
  check(gate.asked.length > 0 && gate.asked[0].toolName === 'run_command', 'command needed approval');
  check(gate.asked.length > 0 && gate.asked[0].preview.includes('node test.js'), 'approval preview shows the command');
  check(!fs.existsSync(root + '/ran.txt'), 'denied command did not run');
  check(Array.from(rec.statuses.values()).includes('denied'), 'call marked denied');
  check(rec.endStatus === 'done', 'turn ended and waits for the user');
}

async function stop(): Promise<void> {
  console.log(`\n== Scenario 4 (${format}): stop while running`);
  const root = makeProject();
  const rec = new Recorder();
  const gate = new ScriptedGate(() => ({ decision: ApprovalDecision.APPROVE, feedback: '' }));
  const s = session(root, ApprovalMode.FULL_AUTO, gate, rec);
  const p = s.send('Run the command `sleep 20 && echo finished` and report its output.');
  setTimeout(() => s.stop(), 8000);
  const t0 = Date.now();
  await p;
  check(rec.endStatus === 'cancelled', 'turn ended as cancelled');
  check(Date.now() - t0 < 19000, 'stop interrupted the running command');
  check(!s.busy, 'session is idle again');
}

async function main(): Promise<void> {
  await fixBug();
  await denial();
  await stop();
  console.log(failures === 0 ? '\nALL PASSED' : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e: Error) => {
  console.error(e);
  process.exit(1);
});
