// Tests the remote workspace layer against the ssh2 test server: connection + platform probe, the
// agent's file system over SFTP, commands with working folders, timeouts and stop, jump hosts,
// reconnecting after the link drops, and the agent's own tools running against the remote machine.
// Usage: node build.mjs remote
import * as fs from 'fs';
import * as path from 'path';
import { BackgroundJobs } from '../../entry/src/main/ets/core/agent/BackgroundJobs';
import { NoUserPrompter } from '../../entry/src/main/ets/core/agent/Interaction';
import { PathGuard } from '../../entry/src/main/ets/core/agent/PathGuard';
import { ReadTracker } from '../../entry/src/main/ets/core/agent/ReadTracker';
import { ToolArgs, ToolContext } from '../../entry/src/main/ets/core/agent/ToolTypes';
import { EditFileTool } from '../../entry/src/main/ets/core/agent/tools/EditFileTool';
import { GrepTool } from '../../entry/src/main/ets/core/agent/tools/GrepTool';
import { ListDirTool } from '../../entry/src/main/ets/core/agent/tools/ListDirTool';
import { ReadFileTool } from '../../entry/src/main/ets/core/agent/tools/ReadFileTool';
import { RunCommandTool } from '../../entry/src/main/ets/core/agent/tools/RunCommandTool';
import { CancelToken } from '../../entry/src/main/ets/core/llm/CancelToken';
import { RemoteCommandRunner } from '../../entry/src/main/ets/core/remote/RemoteCommandRunner';
import { ConnState, RemoteConnection, RemoteEnv } from '../../entry/src/main/ets/core/remote/RemoteConnection';
import { RemoteFs } from '../../entry/src/main/ets/core/remote/RemoteFs';
import { AuthMethod, RemoteHost, RemoteOs } from '../../entry/src/main/ets/core/remote/RemoteHost';
import { RemoteShell } from '../../entry/src/main/ets/core/remote/RemoteShell';
import { crypto, PASSWORD, sftpRoot, sockets, startServer, USER, userKey } from './TestServer';

let failures = 0;
function check(cond: boolean, what: string): void {
  console.log((cond ? '  PASS ' : '  FAIL ') + what);
  if (!cond) {
    failures++;
  }
}

function host(id: string, port: number, over: Partial<RemoteHost> = {}): RemoteHost {
  return {
    id: id, name: 'Test ' + id, host: '127.0.0.1', port: port, username: USER, auth: AuthMethod.PASSWORD,
    jumpHostId: '', startDir: '', lastUsed: 0, ...over
  };
}

function env(hosts: RemoteHost[], trusted: string[]): RemoteEnv {
  return {
    sockets: sockets, crypto: crypto,
    secrets: { password: () => PASSWORD, userKey: () => userKey },
    trust: {
      check: async (h, info) => {
        trusted.push(h.id + ' ' + info.fingerprint);
        return true;
      }
    },
    lookup: (id: string) => hosts.find((h) => h.id === id),
    keepaliveMs: 0, connectTimeoutMs: 5000
  };
}

function ctxFor(conn: RemoteConnection, root: string): ToolContext {
  return {
    paths: new PathGuard(root, false, conn.platform?.home ?? root), fs: new RemoteFs(conn),
    shell: new RemoteCommandRunner(conn), cancel: new CancelToken(), reads: new ReadTracker(),
    host: { planUpdated: () => {}, commandOutput: () => {} }, callId: 'c', prompter: new NoUserPrompter(),
    jobs: new BackgroundJobs(), web: null, subagents: null
  };
}

const args = (o: object): ToolArgs => new ToolArgs(o as Record<string, Object>);

function testShellHelpers(): void {
  console.log('Path and quoting helpers');
  check(RemoteShell.toSftp('C:\\Users\\dev') === '/C:/Users/dev' && RemoteShell.toSftp('/home/x') === '/home/x', 'toSftp');
  check(RemoteShell.toWindows('/C:/Users/dev') === 'C:\\Users\\dev' && RemoteShell.toWindows('/D:') === 'D:\\', 'toWindows');
  check(RemoteShell.sh("it's") === "'it'\\''s'" && RemoteShell.ps("it's") === "'it''s'", 'quoting');
  const enc = RemoteShell.powershell('Write-Output "é"');
  const b64 = enc.substring(enc.lastIndexOf(' ') + 1);
  check(Buffer.from(b64, 'base64').toString('utf16le') === 'Write-Output "é"', 'PowerShell -EncodedCommand is UTF-16LE');
}

async function testConnectionAndFs(): Promise<void> {
  console.log('Connection and files');
  const { port, server } = await startServer({});
  const trusted: string[] = [];
  const h = host('a', port);
  const conn = new RemoteConnection(h, env([h], trusted));
  const states: string[] = [];
  conn.onChange((s) => states.push(s));
  await conn.connect();
  check(states.join(',') === 'connecting,connected', 'state changes: ' + states.join(','));
  check(trusted.length === 1 && trusted[0].startsWith('a SHA256:'), 'host key went through the trust check');
  check(conn.platform !== null && conn.platform.os !== RemoteOs.UNKNOWN && conn.platform.hostname.length > 0,
    'platform probe: ' + JSON.stringify(conn.platform));
  const rfs = new RemoteFs(conn);
  await rfs.writeText('/w/deep/a.txt', 'héllo\nworld\n');
  check(fs.readFileSync(path.join(sftpRoot, 'w/deep/a.txt'), 'utf-8') === 'héllo\nworld\n', 'writeText creates folders (UTF-8)');
  check((await rfs.readText('/w/deep/a.txt')) === 'héllo\nworld\n', 'readText');
  const st = await rfs.stat('/w/deep/a.txt');
  check(st !== null && !st.isDir && st.size === Buffer.byteLength('héllo\nworld\n'), 'stat');
  check((await rfs.stat('/w/missing')) === null, 'stat of a missing path is null');
  await rfs.writeText('/w/b.txt', 'b');
  fs.mkdirSync(path.join(sftpRoot, 'w/.git'));
  const names = (await rfs.list('/w')).map((e) => e.name + (e.isDir ? '/' : ''));
  check(JSON.stringify(names) === JSON.stringify(['deep/', 'b.txt']), 'list sorts folders first and hides .git: ' + names);
  fs.writeFileSync(path.join(sftpRoot, 'w/bin.dat'), Buffer.from([1, 0, 2]));
  try {
    await rfs.readText('/w/bin.dat');
    check(false, 'binary refused');
  } catch (e) {
    check((e as Error).message.includes('binary'), 'binary refused');
  }
  await rfs.writeText('/w/c.txt', 'c');
  await rfs.rename('/w/c.txt', '/w/b.txt');
  check((await rfs.readText('/w/b.txt')) === 'c' && (await rfs.stat('/w/c.txt')) === null, 'rename replaces');
  await rfs.remove('/w');
  check(!fs.existsSync(path.join(sftpRoot, 'w')), 'recursive remove');

  console.log('Agent tools on the remote machine');
  fs.mkdirSync(path.join(sftpRoot, 'proj/src'), { recursive: true });
  fs.writeFileSync(path.join(sftpRoot, 'proj/src/app.py'), 'def add(a, b):\n    return a - b\n');
  const ctx = ctxFor(conn, '/proj');
  check((await new ListDirTool().run(args({}), ctx)).text.includes('app.py'), 'list_dir');
  check((await new GrepTool().run(args({ pattern: 'return a' }), ctx)).text.includes('src/app.py:2:'), 'grep');
  await new ReadFileTool().run(args({ path: 'src/app.py' }), ctx);
  await new EditFileTool().run(args({ path: 'src/app.py', old_string: 'a - b', new_string: 'a + b' }), ctx);
  check(fs.readFileSync(path.join(sftpRoot, 'proj/src/app.py'), 'utf-8').includes('a + b'), 'edit_file over SFTP');
  check((await new ListDirTool().run(args({ path: '/' }), ctx)).text.includes('proj/'), 'full access outside the working folder');
  conn.close();
  server.close();
}

async function testCommands(): Promise<void> {
  console.log('Commands');
  const { port, server } = await startServer({});
  const h = host('c', port);
  const conn = new RemoteConnection(h, env([h], []));
  const run = new RemoteCommandRunner(conn);
  const tmpDir = fs.mkdtempSync(path.join(sftpRoot, 'cwd-')).replace(/\\/g, '/');
  let live = '';
  const r = await run.run('echo "out"; echo "err" >&2; pwd; exit 7', tmpDir, 10000, new CancelToken(), (c) => (live += c));
  check(r.exitCode === 7 && r.output.includes('out') && r.output.includes('err'), 'exit code and both streams');
  check(!r.output.includes('HCPID') && !r.output.includes('\u001e'), 'pid marker is hidden');
  check(live === r.output, 'output streamed live');
  const base = path.basename(tmpDir);
  check(r.output.includes(base), 'runs in the working folder');
  const bad = await run.run('echo hi', '/definitely/missing', 10000, new CancelToken(), () => {});
  check(bad.exitCode === 125, 'missing working folder: exit 125');
  const q = await run.run("printf '%s' \"it's \\$HOME\"", tmpDir, 10000, new CancelToken(), () => {});
  check(q.output === "it's $HOME", 'quoting survives: ' + q.output);
  const t0 = Date.now();
  const slow = await run.run('sleep 20; echo late', tmpDir, 1500, new CancelToken(), () => {});
  check(slow.timedOut && Date.now() - t0 < 8000 && !slow.output.includes('late'), 'timeout ends the command');
  const cancel = new CancelToken();
  setTimeout(() => cancel.cancel(), 800);
  const t1 = Date.now();
  try {
    await run.run('sleep 20', tmpDir, 60000, cancel, () => {});
    check(false, 'stop rejects');
  } catch (e) {
    check(CancelToken.isCancellation(e as Error) && Date.now() - t1 < 5000, 'stop rejects with cancellation');
  }
  check(run.describe().includes('login shell') || run.describe().includes('PowerShell'), 'describe: ' + run.describe().slice(0, 80));
  const bg = new RunCommandTool();
  const ctx = ctxFor(conn, tmpDir);
  const started = await bg.run(args({ command: 'echo started; sleep 1; echo finished', run_in_background: true }), ctx);
  check(started.text.includes('job1'), 'background job on the remote machine');
  const job = ctx.jobs.get('job1');
  await job?.waitForChange(4000, new CancelToken());
  await job?.waitForChange(4000, new CancelToken());
  check(job !== undefined && job.output.includes('finished'), 'background output collected');

  console.log('Reconnect');
  (conn as unknown as { client: { transport: { stream: { close: () => void } } } }).client.transport['stream'].close();
  await new Promise((res) => setTimeout(res, 200));
  check(conn.state === ConnState.FAILED, 'link drop is noticed: ' + conn.state + ' ' + conn.error);
  const again = await run.run('echo back', tmpDir, 10000, new CancelToken(), () => {});
  check(again.output.includes('back') && conn.state === ConnState.CONNECTED, 'next command reconnects');
  conn.close();
  server.close();
}

async function testJumpAndKey(): Promise<void> {
  console.log('Jump host and key login');
  const jump = await startServer({});
  const target = await startServer({ methods: ['publickey'] });
  const j = host('jump', jump.port);
  const t = host('target', target.port, { jumpHostId: 'jump', auth: AuthMethod.KEY });
  const trusted: string[] = [];
  const conn = new RemoteConnection(t, env([j, t], trusted));
  const r = await new RemoteCommandRunner(conn).run('echo via-jump', '/', 10000, new CancelToken(), () => {});
  check(r.output.includes('via-jump'), 'command through the jump host with key login');
  check(trusted.length === 2 && trusted[0].startsWith('jump ') && trusted[1].startsWith('target '), 'both host keys checked');
  const loop = host('loop', jump.port, { jumpHostId: 'loop' });
  try {
    await new RemoteConnection(loop, env([loop], [])).connect();
    check(false, 'jump loop refused');
  } catch (e) {
    check((e as Error).message.includes('loop'), 'jump loop refused');
  }
  const noKey: RemoteEnv = { ...env([t], []), secrets: { password: () => '', userKey: () => null } };
  try {
    await new RemoteConnection(host('k', target.port, { auth: AuthMethod.KEY }), noKey).connect();
    check(false, 'missing key explained');
  } catch (e) {
    check((e as Error).message.includes('No HarmonyCode key'), 'missing key explained');
  }
  conn.close();
  jump.server.close();
  target.server.close();
}

(async () => {
  testShellHelpers();
  await testConnectionAndFs();
  await testCommands();
  await testJumpAndKey();
  fs.rmSync(sftpRoot, { recursive: true, force: true });
  console.log(failures === 0 ? '\nAll remote tests passed.' : `\n${failures} remote test(s) FAILED.`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
