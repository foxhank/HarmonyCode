// Live end-to-end test: a real model works on a "remote computer" only through SSH (the ssh2 test
// server, whose SFTP shows the real disk): it fixes failing tests, runs a server in the background
// and stops it, and asks the user a question with ask_user.
// Usage: node build.mjs agent <account-file> [openai-chat|anthropic]
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { AgentListener, ToolCallView } from '../../entry/src/main/ets/core/agent/AgentEvents';
import { ApprovalMode, ApprovalPolicy } from '../../entry/src/main/ets/core/agent/Approval';
import { AgentSession } from '../../entry/src/main/ets/core/agent/AgentSession';
import { BackgroundJobs } from '../../entry/src/main/ets/core/agent/BackgroundJobs';
import { UserQuestion } from '../../entry/src/main/ets/core/agent/Interaction';
import { PathGuard } from '../../entry/src/main/ets/core/agent/PathGuard';
import { WorkspaceKind } from '../../entry/src/main/ets/core/agent/SystemPrompt';
import { ToolRegistry } from '../../entry/src/main/ets/core/agent/ToolRegistry';
import { ToolOutput } from '../../entry/src/main/ets/core/agent/ToolTypes';
import { ChatModel } from '../../entry/src/main/ets/core/llm/ChatModel';
import { LlmClient } from '../../entry/src/main/ets/core/llm/LlmClient';
import { ApiFormat, ModelInfo, ProviderConfig } from '../../entry/src/main/ets/core/llm/ProviderConfig';
import { RemoteCommandRunner } from '../../entry/src/main/ets/core/remote/RemoteCommandRunner';
import { RemoteConnection } from '../../entry/src/main/ets/core/remote/RemoteConnection';
import { RemoteFs } from '../../entry/src/main/ets/core/remote/RemoteFs';
import { AuthMethod, RemoteHost } from '../../entry/src/main/ets/core/remote/RemoteHost';
import { NodeHttpTransport } from '../agent/NodeHttpTransport';
import { readTestAccount } from '../agent/TestAccount';
import { crypto, sockets, startServer, USER, userKey } from './TestServer';

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

class Recorder implements AgentListener {
  tools: string[] = [];
  args: string[] = [];
  status = '';
  error = '';
  onTurnStart(): void {}
  onStepStart(step: number): void {
    process.stdout.write(`\n  [step ${step}] `);
  }
  onTextDelta(t: string): void {
    process.stdout.write(t);
  }
  onReasoningDelta(): void {}
  onToolCall(c: ToolCallView): void {
    this.tools.push(c.toolName);
    this.args.push(c.argumentsJson);
    process.stdout.write(`\n    -> ${c.toolName} ${c.argumentsJson.substring(0, 120).replace(/\n/g, '\\n')}`);
  }
  onToolStatus(): void {}
  onToolOutput(id: string, o: ToolOutput): void {
    process.stdout.write(`\n       ${o.isError ? 'ERR' : 'ok '} ${o.text.substring(0, 140).replace(/\n/g, ' | ')}`);
  }
  onCommandOutput(): void {}
  onPlan(): void {}
  onUsage(): void {}
  onNotice(): void {}
  onFilesChanged(): void {}
  onTurnEnd(s: string, e: string): void {
    this.status = s;
    this.error = e;
  }
}

/** Git Bash path of a Windows path ("C:\x" -> "/c/x"); unchanged elsewhere. */
function msys(p: string): string {
  return p.replace(/\\/g, '/').replace(/^([A-Za-z]):/, (m, d: string) => '/' + d.toLowerCase());
}

function makeProject(): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hc-remote-agent-'));
  fs.writeFileSync(path.join(dir, 'stats.js'),
    'function mean(xs) {\n  let s = 0;\n  for (let i = 1; i < xs.length; i++) s += xs[i];\n  return s / xs.length;\n}\n' +
    'module.exports = { mean };\n');
  fs.writeFileSync(path.join(dir, 'test.js'),
    "const { mean } = require('./stats');\nconst assert = require('assert');\nassert.strictEqual(mean([2, 4, 6]), 4);\n" +
    "console.log('all tests passed');\n");
  fs.writeFileSync(path.join(dir, 'server.js'),
    "console.log('listening on 4711');\nsetInterval(() => console.log('tick'), 1000);\n");
  return dir;
}

(async () => {
  const { port, server } = await startServer({ realDisk: true, methods: ['publickey'] });
  const dir = makeProject();
  const host: RemoteHost = {
    id: 'pc', name: 'Test PC', host: '127.0.0.1', port: port, username: USER, auth: AuthMethod.KEY, jumpHostId: '',
    startDir: msys(dir), lastUsed: 0
  };
  const conn = new RemoteConnection(host, {
    sockets: sockets, crypto: crypto, secrets: { password: () => '', userKey: () => userKey },
    trust: { check: async () => true }, lookup: () => undefined, keepaliveMs: 0, connectTimeoutMs: 5000
  });
  await conn.connect();
  const shell = new RemoteCommandRunner(conn);
  const questions: UserQuestion[] = [];
  const rec = new Recorder();
  const session = new AgentSession({
    model: new ChatModel(new LlmClient(new NodeHttpTransport()), provider, model), fs: new RemoteFs(conn), shell: shell,
    paths: new PathGuard(conn.startDir(), false, conn.platform?.home ?? ''), tools: ToolRegistry.coding(false),
    policy: new ApprovalPolicy(ApprovalMode.FULL_AUTO), gate: { request: async () => ({ decision: 'approve', feedback: '' }) },
    prompter: { ask: async (q: UserQuestion) => (questions.push(q), 'Hi') }, jobs: new BackgroundJobs(), web: null,
    env: {
      kind: WorkspaceKind.REMOTE, projectName: 'Test PC (dev@127.0.0.1)', root: conn.startDir(), shell: shell.describe(),
      today: '2026-11-04', customInstructions: '', web: false, subagent: false
    },
    maxSteps: 40, temperature: NaN, allowSubagents: true
  }, rec);

  console.log(`== Remote scenario 1 (${format}): fix failing tests, then run a server in the background and stop it`);
  await session.send('In the working folder on this computer, `node test.js` fails. Find and fix the bug, then verify ' +
    'with `node test.js`. After that, start `node server.js` in the background, confirm with command_output that it ' +
    'printed "listening", and stop it with kill_command.');
  check(rec.status === 'done', 'turn finished: ' + rec.status + ' ' + rec.error);
  check(fs.readFileSync(path.join(dir, 'stats.js'), 'utf-8').includes('i = 0'), 'bug fixed on the remote disk (over SFTP)');
  const bg = rec.args.some((a) => a.includes('run_in_background') && a.includes('server.js'));
  check(bg, 'started the server in the background');
  check(rec.tools.includes('command_output') && rec.tools.includes('kill_command'), 'checked and stopped the job');

  console.log(`\n== Remote scenario 2 (${format}): ask the user, then act on the answer`);
  rec.tools = [];
  await session.send('Use ask_user to ask me whether greeting.txt should say "Hello" or "Hi" (offer both as options), ' +
    'then create greeting.txt in the working folder containing exactly my answer and nothing else.');
  check(questions.length === 1 && questions[0].options.length >= 2, 'asked with options: ' + JSON.stringify(questions[0]?.options));
  const g = path.join(dir, 'greeting.txt');
  check(fs.existsSync(g) && fs.readFileSync(g, 'utf-8').trim() === 'Hi', 'acted on the answer: ' +
    (fs.existsSync(g) ? JSON.stringify(fs.readFileSync(g, 'utf-8')) : 'missing'));

  session.dispose();
  conn.close();
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });
  console.log(failures === 0 ? '\nALL PASSED' : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
