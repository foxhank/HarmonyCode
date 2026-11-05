// Interop test of HarmonyCode Link: the phone side (the app's ArkTS sources, under Node) against the
// real desktop app (desktop/harmonycode_desktop, started headless). Pairing and its security checks,
// two-way sync with real-time change events, conflicts, large files, commands, tampering, LZ4.
// Usage: node build.mjs link      (needs desktop/.venv: see desktop/README.md)
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { ChildProcess, spawn, spawnSync } from 'child_process';
import { CancelToken } from '../../entry/src/main/ets/core/llm/CancelToken';
import { LinkClient } from '../../entry/src/main/ets/core/link/LinkClient';
import { LinkPairing, PairingOffer } from '../../entry/src/main/ets/core/link/LinkPairing';
import { LinkEntry, ZERO_HASH } from '../../entry/src/main/ets/core/link/LinkProtocol';
import { LinkAuth } from '../../entry/src/main/ets/core/link/LinkSession';
import { LinkSync } from '../../entry/src/main/ets/core/link/LinkSync';
import { Lz4 } from '../../entry/src/main/ets/core/link/Lz4';
import { ByteStream, Ed25519KeyPair } from '../../entry/src/main/ets/core/remote/ssh/SshCrypto';
import { NodeSocketFactory, NodeSshCrypto } from '../remote/NodeSsh';
import { MemoryStore, NodeSyncFs } from '../remote/NodeSyncFs';

let failures = 0;
function check(cond: boolean, what: string): void {
  console.log((cond ? '  PASS ' : '  FAIL ') + what);
  if (!cond) {
    failures++;
  }
}

const crypto = new NodeSshCrypto();
const sockets = new NodeSocketFactory();
const repo = path.resolve(__dirname, '../../..');
const py = path.join(repo, 'desktop', '.venv', process.platform === 'win32' ? 'Scripts/python.exe' : 'bin/python');
const SECRET_HEX = '00112233445566778899aabbccddeeff';
const sleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));
const slash = (p: string): string => p.replace(/\\/g, '/');

interface Desktop {
  proc: ChildProcess;
  port: number;
  offer: PairingOffer;
  workspace: string;
}

async function startDesktop(config: string, workspace: string): Promise<Desktop> {
  const proc = spawn(py, ['-m', 'harmonycode_desktop', '--headless', '--port', '0', '--config', config, '--workspace',
    workspace, '--name', 'Test Desktop', '--pair-secret', SECRET_HEX], { cwd: path.join(repo, 'desktop') });
  let out = '';
  proc.stderr?.on('data', (d) => process.stderr.write('[desktop] ' + d));
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('desktop did not start:\n' + out)), 20000);
    proc.stdout?.on('data', (d: Buffer) => {
      out += d.toString();
      const port = /HCLINK_READY (\d+)/.exec(out);
      const uri = /HCLINK_PAIR (\S+)/.exec(out);
      if (port && uri) {
        clearTimeout(t);
        // Point the addresses at localhost (the LAN address may not be reachable from here).
        const offer = LinkPairing.parse(uri[1]);
        offer.addresses = [{ host: '127.0.0.1', port: Number(port[1]) }];
        resolve({ proc, port: Number(port[1]), offer, workspace });
      }
    });
    proc.on('exit', (code) => reject(new Error(`desktop exited (${code}):\n${out}`)));
  });
}

function auth(id: Ed25519KeyPair, offer: PairingOffer, pair: boolean, name = 'Test Phone'): LinkAuth {
  return { identity: id, deviceName: name, serverKey: offer.serverKey, pairSecret: pair ? offer.secret : new Uint8Array(0) };
}

async function connect(d: Desktop, a: LinkAuth): Promise<LinkClient> {
  return (await LinkPairing.connect(sockets, crypto, d.offer.addresses, a, 5000)).client;
}

async function expectFail(p: Promise<unknown>, contains: string, what: string): Promise<void> {
  try {
    await p;
    check(false, what + ' (expected an error)');
  } catch (e) {
    const msg = (e as Error).message;
    check(msg.includes(contains), `${what}: "${msg}"`);
  }
}

function testLz4Interop(): void {
  console.log('LZ4 between ArkTS and Python');
  const samples = [Buffer.from('const x = 1;\n'.repeat(2000)), crypto.random(20000), Buffer.alloc(70000),
    Buffer.from('ab'.repeat(40000) + 'tail')];
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hc-lz4-'));
  samples.forEach((s, i) => {
    fs.writeFileSync(path.join(dir, `${i}.raw`), s);
    fs.writeFileSync(path.join(dir, `${i}.ts.lz4`), Lz4.compress(new Uint8Array(s)));
  });
  const script = `
import sys, pathlib
sys.path.insert(0, r'${path.join(repo, 'desktop')}')
from harmonycode_desktop import lz4
d = pathlib.Path(r'${dir}')
for i in range(${samples.length}):
    raw = (d / f'{i}.raw').read_bytes()
    assert lz4.decompress((d / f'{i}.ts.lz4').read_bytes(), len(raw)) == raw, f'py decode {i}'
    (d / f'{i}.py.lz4').write_bytes(lz4.compress(raw))
print('ok')`;
  const r = spawnSync(py, ['-c', script], { encoding: 'utf-8' });
  check(r.stdout.trim() === 'ok', 'Python decompresses ArkTS output' + (r.stderr ? ': ' + r.stderr : ''));
  let ok = true;
  samples.forEach((s, i) => {
    const back = Lz4.decompress(new Uint8Array(fs.readFileSync(path.join(dir, `${i}.py.lz4`))), s.length);
    ok = ok && Buffer.compare(Buffer.from(back), s) === 0;
  });
  check(ok, 'ArkTS decompresses Python output');
  const text = Lz4.compress(new Uint8Array(samples[0]));
  check(text.length < samples[0].length / 10, `source code compresses well (${samples[0].length} -> ${text.length})`);
}

/** Lets a test corrupt the next byte the phone sends. */
class TamperStream implements ByteStream {
  corrupt = false;
  constructor(private inner: ByteStream) {}
  write(d: Uint8Array): void {
    if (this.corrupt && d.length > 20) {
      this.corrupt = false;
      const c = d.slice();
      c[c.length - 3] ^= 0x40;
      this.inner.write(c);
      return;
    }
    this.inner.write(d);
  }
  setOnData(l: (d: Uint8Array) => void): void {
    this.inner.setOnData(l);
  }
  setOnClose(l: (e: string) => void): void {
    this.inner.setOnClose(l);
  }
  close(): void {
    this.inner.close();
  }
}

async function testPairing(d: Desktop, phone: Ed25519KeyPair): Promise<void> {
  console.log('Pairing and authentication');
  const wrongSecret: LinkAuth = { ...auth(phone, d.offer, true), pairSecret: new Uint8Array(16) };
  await expectFail(connect(d, wrongSecret), 'pairing code is wrong', 'wrong pairing secret refused');
  const imposter = { ...d.offer, serverKey: crypto.ed25519Generate().publicKey };
  await expectFail(connect(d, auth(phone, imposter, true)), 'identity does not match', 'impostor desktop key detected');
  await expectFail(connect(d, auth(phone, d.offer, false)), 'not paired', 'unpaired phone cannot resume');
  const c = await connect(d, auth(phone, d.offer, true));
  check(c.info.name === 'Test Desktop' && c.info.hostname.length > 0, 'paired: ' + JSON.stringify(c.info));
  c.close();
  const again = await connect(d, auth(phone, d.offer, false));
  check(!again.isClosed, 'resumes later with the stored identities');
  again.close();
  const stranger = crypto.ed25519Generate();
  await expectFail(connect(d, auth(stranger, d.offer, false)), 'not paired', 'another phone cannot resume');

  const stream = new TamperStream(await sockets.connect('127.0.0.1', d.port, 5000));
  const { LinkSession } = await import('../../entry/src/main/ets/core/link/LinkSession');
  const session = await LinkSession.open(stream, crypto, auth(phone, d.offer, false));
  const tc = new LinkClient(session, crypto);
  stream.corrupt = true;
  await expectFail(tc.list(''), '', 'a tampered record makes the desktop drop the connection');
  await sleep(200);
  check(tc.isClosed, 'connection closed after tampering');
}

async function testSync(d: Desktop, phone: Ed25519KeyPair): Promise<void> {
  console.log('Two-way sync');
  const client = await connect(d, auth(phone, d.offer, false));
  const events: LinkEntry[][] = [];
  client.onChanged((e) => events.push(e));
  const local = slash(fs.mkdtempSync(path.join(os.tmpdir(), 'hc-link-phone-')));
  const desk = path.join(d.workspace, 'demo');
  const w = (root: string, rel: string, text: string | Buffer): void => {
    fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
    fs.writeFileSync(path.join(root, rel), text);
  };
  const rd = (root: string, rel: string): string => fs.readFileSync(path.join(root, rel), 'utf-8');
  w(local, 'main.py', 'print("hello")\n');
  w(local, 'src/lib.py', 'X = 1\n');
  w(local, 'node_modules/big/a.js', 'deps');
  const big = Buffer.concat([Buffer.from('line of code\n'.repeat(100000)), crypto.random(300000)]);
  w(local, 'assets/big.bin', big);
  const sync = new LinkSync(new NodeSyncFs(), local, 'demo', crypto, new MemoryStore());
  let r = await sync.sync(client, true);
  check(r.uploaded.length === 3 && rd(desk, 'src/lib.py') === 'X = 1\n', 'first sync uploads: ' + r.summary());
  check(Buffer.compare(fs.readFileSync(path.join(desk, 'assets/big.bin')), big) === 0,
    `large file in chunks (${(big.length / 1e6).toFixed(1)} MB)`);
  check(!fs.existsSync(path.join(desk, 'node_modules')), 'dependency folders stay on the phone');
  await sleep(1600);
  check(!events.some((ev) => ev.some((e) => e.path === 'demo/main.py')), 'no echo of the phone\'s own writes');

  // Desktop edits: the CHANGED event arrives by itself, then a sync applies it.
  events.length = 0;
  w(desk, 'src/lib.py', 'X = 2  # edited on the desktop\n');
  w(desk, 'out/result.txt', 'built on desktop\n');
  w(desk, 'node_modules/dep/i.js', 'desktop deps');
  const seenPaths = (): string[] => events.flat().map((e) => e.path);
  for (let i = 0; i < 40 && !(seenPaths().includes('demo/src/lib.py') && seenPaths().includes('demo/out/result.txt')); i++) {
    await sleep(100);
  }
  check(events.length > 0 && events.flat().some((e) => e.path === 'demo/src/lib.py'),
    'desktop change announced in real time: ' + events.flat().map((e) => e.path).join(', '));
  check(sync.applyEvent(events.flat()), 'event concerns the project');
  r = await sync.sync(client, false);
  check(rd(local, 'src/lib.py').includes('edited on the desktop') && rd(local, 'out/result.txt') === 'built on desktop\n',
    'desktop edits came to the phone: ' + r.summary());
  check(!fs.existsSync(path.join(local, 'node_modules/dep')), 'desktop dependencies stay there');

  // Phone edit and both-side deletions.
  w(local, 'main.py', 'print("v2")\n');
  fs.rmSync(path.join(local, 'assets/big.bin'));
  fs.rmSync(path.join(desk, 'out/result.txt'));
  await sleep(900);
  sync.applyEvent([{ path: 'demo/out/result.txt', size: 0, mtime: 0, hash: ZERO_HASH, deleted: true }]);
  r = await sync.sync(client, true);
  check(rd(desk, 'main.py') === 'print("v2")\n', 'phone edit went up');
  check(!fs.existsSync(path.join(desk, 'assets/big.bin')), 'phone deletion went up');
  check(!fs.existsSync(path.join(local, 'out/result.txt')), 'desktop deletion came down: ' + r.summary());

  // Conflict.
  w(local, 'main.py', 'print("phone")\n');
  w(desk, 'main.py', 'print("desktop, longer")\n');
  await sleep(900);
  r = await sync.sync(client, true);
  check(r.conflicts.includes('main.py') && rd(desk, 'main.py') === 'print("phone")\n' &&
    rd(local, 'main.py.conflict') === 'print("desktop, longer")\n', 'conflict: phone wins, desktop copy kept');

  // Race: the desktop changes a file after the phone listed it; the guarded write refuses, then it re-decides.
  await sync.sync(client, true);
  w(local, 'src/lib.py', 'X = 3  # phone\n');
  w(desk, 'src/lib.py', 'X = 4  # desktop, meanwhile\n');
  r = await sync.sync(client, false); // stale view of the desktop
  check(rd(desk, 'src/lib.py') === 'X = 3  # phone\n' && rd(local, 'src/lib.py.conflict') === 'X = 4  # desktop, meanwhile\n',
    'stale write refused by compare-and-swap, then resolved as a conflict: ' + r.summary());

  // Paths are confined to the workspace.
  const bad = await client.put('../escape.txt', ZERO_HASH, new Uint8Array([1]));
  check(bad.status === 2 && !fs.existsSync(path.join(d.workspace, '..', 'escape.txt')), 'path escape refused: ' + bad.message);
  const abs = await client.put('C:/Windows/x.txt', ZERO_HASH, new Uint8Array([1]));
  check(abs.status === 2, 'drive path refused');

  // Second phone sees the first one's writes as events.
  const other = crypto.ed25519Generate();
  // (pair it: the desktop's fixed test secret is reusable)
  const c2 = await connect(d, auth(other, d.offer, true, 'Tablet'));
  const seen: string[] = [];
  c2.onChanged((e) => e.forEach((x) => seen.push(x.path)));
  w(local, 'shared.txt', 'from phone 1\n');
  await sync.sync(client, false);
  for (let i = 0; i < 30 && !seen.includes('demo/shared.txt'); i++) {
    await sleep(100);
  }
  check(seen.includes('demo/shared.txt'), 'other devices get the change in real time');
  c2.close();
  client.close();
}

async function testExec(d: Desktop, phone: Ed25519KeyPair): Promise<void> {
  console.log('Commands');
  const client = await connect(d, auth(phone, d.offer, false));
  const win = client.info.os === 'Windows';
  let out = '';
  const r = await client.exec(win ? 'Write-Output "hi from $env:COMPUTERNAME"; (Get-Location).Path; exit 3' :
    'echo "hi from $(hostname)"; pwd; exit 3', 'demo/src', 30000, new CancelToken(), (t) => (out += t));
  check(r.exitCode === 3 && out.includes('hi from') && /demo[\\/]src/.test(out), 'output, exit code, working folder: ' +
    out.trim().replace(/\s+/g, ' '));
  const big = await client.exec(win ? '1..20000 | ForEach-Object { "line $_" }' : 'seq 1 20000 | sed "s/^/line /"', '', 60000,
    new CancelToken(), () => {});
  check(big.exitCode === 0, 'long output streams');
  const cancel = new CancelToken();
  setTimeout(() => cancel.cancel(), 1500);
  const t0 = Date.now();
  const k = await client.exec(win ? 'Start-Sleep -Seconds 30' : 'sleep 30', '', 60000, cancel, () => {});
  check(Date.now() - t0 < 10000 && k.exitCode !== 0, `stop kills the command (${Date.now() - t0} ms)`);
  const to = await client.exec(win ? 'Start-Sleep -Seconds 30' : 'sleep 30', '', 1500, new CancelToken(), () => {});
  check(to.timedOut, 'timeout');
  client.close();
}

(async () => {
  if (!fs.existsSync(py)) {
    console.error('desktop/.venv is missing; see desktop/README.md');
    process.exit(2);
  }
  testLz4Interop();
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hc-link-'));
  const d = await startDesktop(path.join(root, 'config'), path.join(root, 'workspace'));
  const phone = crypto.ed25519Generate();
  try {
    await testPairing(d, phone);
    await testSync(d, phone);
    await testExec(d, phone);
  } finally {
    d.proc.kill();
  }
  console.log(failures === 0 ? '\nAll Link tests passed.' : `\n${failures} Link test(s) FAILED.`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
