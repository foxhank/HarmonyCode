// Tests two-way project sync (phone folder <-> computer folder over SFTP) and running a phone project's
// commands on the computer, against the ssh2 test server.
// Usage: node build.mjs sync
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { CancelToken } from '../../entry/src/main/ets/core/llm/CancelToken';
import { ProjectSync, SyncReport } from '../../entry/src/main/ets/core/remote/ProjectSync';
import { RemoteConnection, RemoteEnv } from '../../entry/src/main/ets/core/remote/RemoteConnection';
import { AuthMethod, RemoteHost } from '../../entry/src/main/ets/core/remote/RemoteHost';
import { RemoteProjectRunner } from '../../entry/src/main/ets/core/remote/RemoteProjectRunner';
import { MemoryStore, NodeSyncFs } from './NodeSyncFs';
import { crypto, PASSWORD, sftpRoot, sockets, startServer, USER } from './TestServer';

let failures = 0;
function check(cond: boolean, what: string): void {
  console.log((cond ? '  PASS ' : '  FAIL ') + what);
  if (!cond) {
    failures++;
  }
}

function env(): RemoteEnv {
  return {
    sockets: sockets, crypto: crypto, secrets: { password: () => PASSWORD, userKey: () => null },
    trust: { check: async () => true }, lookup: () => undefined, keepaliveMs: 0, connectTimeoutMs: 5000
  };
}

function host(port: number): RemoteHost {
  return { id: 'pc', name: 'PC', host: '127.0.0.1', port: port, username: USER, auth: AuthMethod.PASSWORD, jumpHostId: '',
    startDir: '', lastUsed: 0 };
}

const read = (p: string): string => fs.readFileSync(p, 'utf-8');
const write = (p: string, s: string): void => {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, s);
};

async function testSync(): Promise<void> {
  console.log('Two-way sync');
  const { port, server } = await startServer({});
  const conn = new RemoteConnection(host(port), env());
  const sftp = await conn.sftp();
  const phone = fs.mkdtempSync(path.join(os.tmpdir(), 'hc-phone-')).replace(/\\/g, '/');
  const pc = path.join(sftpRoot, 'proj');
  write(path.join(phone, 'main.py'), 'print("v1")\n');
  write(path.join(phone, 'src/util.py'), 'X = 1\n');
  write(path.join(phone, 'node_modules/big/index.js'), 'phone deps\n');
  fs.writeFileSync(path.join(phone, 'logo.bin'), Buffer.from([0, 1, 2, 255, 0, 7]));
  const store = new MemoryStore();
  const sync = new ProjectSync(new NodeSyncFs(), phone, '/proj', store);
  const go = (): Promise<SyncReport> => sync.sync(sftp, new CancelToken());

  let r = await go();
  check(r.uploaded.length === 3 && read(path.join(pc, 'src/util.py')) === 'X = 1\n', 'first sync uploads: ' + r.summary());
  check(!fs.existsSync(path.join(pc, 'node_modules')), 'dependency folders are not synced');
  check(Buffer.compare(fs.readFileSync(path.join(pc, 'logo.bin')), Buffer.from([0, 1, 2, 255, 0, 7])) === 0, 'binary files');
  r = await go();
  check(r.total === 0, 'nothing to do when nothing changed: ' + r.summary());

  write(path.join(phone, 'main.py'), 'print("v2 from phone")\n');
  write(path.join(pc, 'src/util.py'), 'X = 2  # edited on the pc\n');
  write(path.join(pc, 'out/report.txt'), 'generated\n');
  write(path.join(pc, 'node_modules/dep/index.js'), 'pc deps\n');
  r = await go();
  check(read(path.join(pc, 'main.py')) === 'print("v2 from phone")\n', 'phone edit goes up');
  check(read(path.join(phone, 'src/util.py')).includes('edited on the pc'), 'computer edit comes back');
  check(read(path.join(phone, 'out/report.txt')) === 'generated\n', 'new computer file comes back');
  check(!fs.existsSync(path.join(phone, 'node_modules/dep')), 'computer dependencies stay there');
  check(r.uploaded.length === 1 && r.downloaded.length === 2, 'report: ' + r.summary());

  fs.rmSync(path.join(phone, 'logo.bin'));
  fs.rmSync(path.join(pc, 'out/report.txt'));
  r = await go();
  check(!fs.existsSync(path.join(pc, 'logo.bin')) && r.deletedRemote.includes('logo.bin'), 'phone deletion goes up');
  check(!fs.existsSync(path.join(phone, 'out/report.txt')) && r.deletedLocal.includes('out/report.txt'), 'computer deletion comes back');

  write(path.join(phone, 'main.py'), 'print("phone wins")\n');
  write(path.join(pc, 'main.py'), 'print("pc change, longer")\n');
  r = await go();
  check(r.conflicts.includes('main.py') && read(path.join(pc, 'main.py')) === 'print("phone wins")\n' &&
    read(path.join(phone, 'main.py.conflict')) === 'print("pc change, longer")\n', 'conflict keeps both versions');

  // A fresh manifest (e.g. another phone) against an existing folder: equal files are not conflicts.
  const fresh = new ProjectSync(new NodeSyncFs(), phone, '/proj', new MemoryStore());
  r = await fresh.sync(sftp, new CancelToken());
  check(r.conflicts.length === 0, 'identical files on both sides are not conflicts: ' + r.summary());
  check(sync.toRemote(phone + '/src') === '/proj/src' && sync.toRemote('/elsewhere') === '', 'path mapping');
  conn.close();
  server.close();
}

function msys(p: string): string {
  return p.replace(/\\/g, '/').replace(/^([A-Za-z]):/, (m, d: string) => '/' + d.toLowerCase());
}

async function testRunner(): Promise<void> {
  console.log('Commands of a phone project on the computer');
  const { port, server } = await startServer({ realDisk: true });
  const conn = new RemoteConnection(host(port), env());
  await conn.connect();
  const phone = fs.mkdtempSync(path.join(os.tmpdir(), 'hc-phone-')).replace(/\\/g, '/');
  const pcDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hc-pc-'));
  write(path.join(phone, 'app.js'), 'console.log("hello from " + process.platform)\n');
  write(path.join(phone, 'lib/x.txt'), 'x\n');
  const events: string[] = [];
  const sync = new ProjectSync(new NodeSyncFs(), phone, msys(pcDir), new MemoryStore());
  const runner = new RemoteProjectRunner(conn, sync, {
    syncStarted: () => events.push('start'),
    syncFinished: (rep, err) => events.push(err.length > 0 ? 'error ' + err : 'done ' + (rep?.summary() ?? ''))
  });
  const r = await runner.run('node ../app.js && echo built > dist.txt && pwd', phone + '/lib', 30000, new CancelToken(), () => {});
  check(r.exitCode === 0 && r.output.includes('hello from'), 'ran on the computer: ' + r.output.trim().split('\n')[0]);
  check(r.output.includes('/lib'), 'in the matching folder');
  check(fs.existsSync(path.join(pcDir, 'app.js')), 'files were synced before running');
  check(read(path.join(phone, 'lib/dist.txt')).trim() === 'built', 'files the command made came back to the phone');
  check(events.length === 4 && events[0] === 'start' && events[3].startsWith('done'), 'sync events: ' + events.join(' | '));
  check(runner.describe().includes('mirrored to'), 'describes the mirroring');
  check(RemoteProjectRunner.defaultRemoteDir('/home/dev', 'My App!') === '/home/dev/HarmonyCode/My-App-', 'default folder');
  conn.close();
  server.close();
  fs.rmSync(pcDir, { recursive: true, force: true });
}

(async () => {
  await testSync();
  await testRunner();
  console.log(failures === 0 ? '\nAll sync tests passed.' : `\n${failures} sync test(s) FAILED.`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
