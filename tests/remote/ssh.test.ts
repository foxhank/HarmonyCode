// Tests HarmonyCode's SSH client against an independent SSH server (the ssh2 npm package), over real
// TCP on 127.0.0.1: every key exchange, cipher, MAC and host key type the client offers; password,
// keyboard-interactive and public-key login; commands; a terminal; SFTP; jump hosts and re-keying.
// Usage: node build.mjs ssh
import * as fs from 'fs';
import * as net from 'net';
import { Base64 } from '../../entry/src/main/ets/core/remote/ssh/Bytes';
import { ChannelStream } from '../../entry/src/main/ets/core/remote/ssh/SshChannel';
import { SshAuth, SshClient } from '../../entry/src/main/ets/core/remote/ssh/SshClient';
import { SshKeys, UserKey } from '../../entry/src/main/ets/core/remote/ssh/SshKeys';
import { HostKeyInfo } from '../../entry/src/main/ets/core/remote/ssh/SshTransport';
import { SftpClient, SftpError, SftpStatus } from '../../entry/src/main/ets/core/remote/ssh/SftpClient';
import { crypto, hostKeys, PASSWORD, sftpRoot, sockets, ssh2, startServer, USER, userKey } from './TestServer';

let failures = 0;
function check(cond: boolean, what: string): void {
  console.log((cond ? '  PASS ' : '  FAIL ') + what);
  if (!cond) {
    failures++;
  }
}

function auth(over: Partial<SshAuth> = {}): SshAuth {
  return { username: USER, password: PASSWORD, key: null, ...over };
}

async function connect(port: number, a: SshAuth, onHostKey?: (i: HostKeyInfo) => boolean): Promise<SshClient> {
  const stream = await sockets.connect('127.0.0.1', port, 5000);
  return SshClient.connect(stream, crypto, {
    auth: a,
    verifyHostKey: async (i: HostKeyInfo) => (onHostKey ? onHostKey(i) : true),
    keepaliveMs: 0,
    onBanner: () => {}
  });
}

async function expectFail(p: Promise<unknown>, contains: string, what: string): Promise<void> {
  try {
    await p;
    check(false, what + ' (expected an error)');
  } catch (e) {
    const msg = (e as Error).message;
    check(msg.indexOf(contains) >= 0, `${what}: "${msg}"`);
  }
}

async function algorithmMatrix(): Promise<void> {
  console.log('Algorithms');
  const cases: Array<[string, object, string?]> = [
    ['kex curve25519-sha256', { kex: ['curve25519-sha256'] }],
    ['kex curve25519-sha256@libssh.org', { kex: ['curve25519-sha256@libssh.org'] }],
    ['kex diffie-hellman-group14-sha256', { kex: ['diffie-hellman-group14-sha256'] }],
    ['cipher aes256-gcm', { cipher: ['aes256-gcm@openssh.com'] }],
    ['cipher aes128-gcm', { cipher: ['aes128-gcm@openssh.com'] }],
    ['aes256-ctr + hmac-sha2-256-etm', { cipher: ['aes256-ctr'], hmac: ['hmac-sha2-256-etm@openssh.com'] }],
    ['aes128-ctr + hmac-sha2-512-etm', { cipher: ['aes128-ctr'], hmac: ['hmac-sha2-512-etm@openssh.com'] }],
    ['aes256-ctr + hmac-sha2-256', { cipher: ['aes256-ctr'], hmac: ['hmac-sha2-256'] }],
    ['aes128-ctr + hmac-sha2-512', { cipher: ['aes128-ctr'], hmac: ['hmac-sha2-512'] }],
    ['host key ecdsa-sha2-nistp256', { serverHostKey: ['ecdsa-sha2-nistp256'] }, hostKeys.ecdsa],
    ['host key rsa-sha2-512', { serverHostKey: ['rsa-sha2-512'] }, hostKeys.rsa],
    ['host key rsa-sha2-256', { serverHostKey: ['rsa-sha2-256'] }, hostKeys.rsa]
  ];
  for (const [name, algorithms, hostKey] of cases) {
    const { port, server } = await startServer({ algorithms, hostKey });
    try {
      const c = await connect(port, auth());
      const r = await c.exec('echo hello-$((40+2))');
      check(r.exitCode === 0 && r.stdout.trim() === 'hello-42', `${name}: exec works`);
      c.close();
    } catch (e) {
      check(false, `${name}: ${(e as Error).message}`);
    }
    server.close();
  }
}

async function authAndHostKeys(): Promise<void> {
  console.log('Login and host keys');
  const { port, server } = await startServer({});
  let seen: HostKeyInfo | null = null;
  const c = await connect(port, auth(), (i) => {
    seen = i;
    return true;
  });
  const info = seen as unknown as HostKeyInfo;
  const pub = ssh2.utils.parseKey(hostKeys.ed25519).getPublicSSH();
  const expected = 'SHA256:' + require('crypto').createHash('sha256').update(pub).digest('base64').replace(/=+$/, '');
  check(info !== null && info.algorithm === 'ssh-ed25519' && info.fingerprint === expected,
    'host key info matches the server key: ' + (info ? info.fingerprint : ''));
  c.close();
  await expectFail(connect(port, auth(), () => false), 'not trusted', 'rejected host key stops the connection');
  const dead = net.createServer(() => {});
  await new Promise<void>((res) => dead.listen(0, '127.0.0.1', () => res()));
  await expectFail(sockets.connect('127.0.0.1', 1, 2000), '', 'closed port is reported');
  dead.close();
  await expectFail(connect(port, auth({ password: 'wrong' })), 'Login failed', 'wrong password');
  const k = await connect(port, auth({ password: '', key: userKey }));
  check(!k.isClosed, 'public-key login with a generated Ed25519 key');
  k.close();
  const parsed = SshKeys.fromOpenSsh(SshKeys.toOpenSsh(crypto, userKey));
  check(Base64.encode(parsed.pair.seed) === Base64.encode(userKey.pair.seed) && parsed.comment === userKey.comment,
    'OpenSSH private key format round trip');
  const viaSsh2 = ssh2.utils.parseKey(SshKeys.toOpenSsh(crypto, userKey));
  check(!(viaSsh2 instanceof Error) && viaSsh2.type === 'ssh-ed25519', 'ssh2 reads our private key file');
  const other = SshKeys.generate(crypto, 'other');
  await expectFail(connect(port, auth({ password: '', key: other })), 'rejected the key', 'unknown key is rejected');
  server.close();

  const kbd = await startServer({ methods: ['keyboard-interactive'] });
  const kc = await connect(kbd.port, auth());
  check(!kc.isClosed, 'keyboard-interactive login');
  kc.close();
  await expectFail(connect(kbd.port, auth({ password: 'nope' })), 'Login failed', 'keyboard-interactive wrong password');
  kbd.server.close();

  const keyOnly = await startServer({ methods: ['publickey'] });
  await expectFail(connect(keyOnly.port, auth()), 'only accepts key login', 'key-only server explains itself');
  keyOnly.server.close();
}

async function commandsAndShell(): Promise<void> {
  console.log('Commands and terminal');
  let serverClient: any = null;
  const { port, server, resizes } = await startServer({ onClient: (c) => (serverClient = c) });
  const c = await connect(port, auth());
  const r = await c.exec('echo out; echo err >&2; exit 3');
  check(r.exitCode === 3 && r.stdout.trim() === 'out' && r.stderr.trim() === 'err', 'exit status and stderr');
  const big = await c.exec('head -c 3000000 /dev/zero | tr "\\0" "x"');
  check(big.stdout.length === 3000000, 'large output with flow control: ' + big.stdout.length);
  const utf = await c.exec('printf "\\xe4\\xbd\\xa0\\xe5\\xa5\\xbd"');
  check(utf.stdout === '你好', 'UTF-8 output: ' + utf.stdout);
  const results = await Promise.all([c.exec('echo a'), c.exec('echo b'), c.exec('echo c')]);
  check(results.map((x) => x.stdout.trim()).join('') === 'abc', 'parallel channels');

  // stdin + EOF
  const ch = await c.openSession();
  let echoed = '';
  ch.setOnData((d) => (echoed += Buffer.from(d).toString()));
  await ch.exec('cat');
  ch.writeText('piped-input');
  ch.eof();
  await new Promise<void>((res) => ch.onClose(() => res()));
  check(echoed === 'piped-input' && ch.exitStatus === 0, 'stdin and EOF');

  // terminal
  const sh = await c.openSession();
  let screen = '';
  sh.setOnData((d) => (screen += Buffer.from(d).toString()));
  const ptyOk = await sh.requestPty('xterm-256color', 100, 30);
  const shellOk = await sh.shell();
  sh.resize(120, 40);
  sh.writeText('ls\r');
  await new Promise((res) => setTimeout(res, 300));
  sh.writeText('exit\r');
  await new Promise<void>((res) => sh.onClose(() => res()));
  check(ptyOk && shellOk && screen.indexOf('welcome') >= 0 && screen.indexOf('echo:ls') >= 0, 'interactive shell');
  check(JSON.stringify(resizes) === JSON.stringify([[100, 30], [120, 40]]), 'pty size and resize: ' + JSON.stringify(resizes));

  // server-initiated re-key, then keep working
  serverClient.rekey();
  await new Promise((res) => setTimeout(res, 300));
  const after = await c.exec('echo after-rekey');
  check(after.stdout.trim() === 'after-rekey', 'works after a server-initiated re-key');
  c.close();
  await new Promise((res) => setTimeout(res, 100));
  check(c.isClosed, 'close');
  server.close();
}

async function sftp(): Promise<void> {
  console.log('SFTP');
  const { port, server } = await startServer({});
  const c = await connect(port, auth());
  const s = await SftpClient.open(c);
  check((await s.realpath('.')) === '/', 'realpath');
  await s.mkdir('/proj');
  const data = new Uint8Array(200 * 1024 + 123).map((_, i) => (i * 7) & 0xff);
  await s.writeFile('/proj/data.bin', data);
  const back = await s.readFile('/proj/data.bin', 10 * 1024 * 1024);
  check(back.length === data.length && Buffer.compare(Buffer.from(back), Buffer.from(data)) === 0, 'write + read 200 KB');
  await s.writeFile('/proj/a.txt', new TextEncoder().encode('hello'));
  await s.writeFile('/proj/a.txt', new TextEncoder().encode('hi'));
  check(Buffer.from(await s.readFile('/proj/a.txt', 1000)).toString() === 'hi', 'overwrite truncates');
  for (let i = 0; i < 7; i++) {
    await s.writeFile(`/proj/f${i}.txt`, new Uint8Array(i));
  }
  const names = (await s.list('/proj')).map((e) => e.name).sort();
  check(names.length === 9 && names.indexOf('f6.txt') >= 0, 'list over several READDIR rounds: ' + names.length);
  check((await s.stat('/proj')).isDir && !(await s.stat('/proj/a.txt')).isDir, 'stat type');
  check((await s.stat('/proj/f5.txt')).size === 5, 'stat size');
  await s.rename('/proj/a.txt', '/proj/b.txt');
  check((await s.statOrNull('/proj/a.txt')) === null && (await s.statOrNull('/proj/b.txt')) !== null, 'rename');
  try {
    await s.readFile('/missing.txt', 100);
    check(false, 'missing file error');
  } catch (e) {
    check(e instanceof SftpError && (e as SftpError).code === SftpStatus.NO_SUCH_FILE, 'missing file error code');
  }
  await expectFail(s.readFile('/proj/data.bin', 1000), 'too large', 'size limit');
  for (const n of await s.list('/proj')) {
    await s.remove('/proj/' + n.name);
  }
  await s.rmdir('/proj');
  check((await s.statOrNull('/proj')) === null, 'remove + rmdir');
  s.close();
  c.close();
  server.close();
}

async function jumpHost(): Promise<void> {
  console.log('Jump host');
  const jump = await startServer({});
  const target = await startServer({ hostKey: hostKeys.rsa, algorithms: { serverHostKey: ['rsa-sha2-256'] } });
  const j = await connect(jump.port, auth());
  const tunnel = await j.openDirectTcpip('127.0.0.1', target.port);
  const t = await SshClient.connect(new ChannelStream(tunnel), crypto, {
    auth: auth(), verifyHostKey: async () => true, keepaliveMs: 0, onBanner: () => {}
  });
  const r = await t.exec('echo through-the-jump');
  check(r.stdout.trim() === 'through-the-jump', 'command on a host reached through a jump host');
  t.close();
  j.close();
  jump.server.close();
  target.server.close();
}

async function keepalive(): Promise<void> {
  console.log('Keepalive');
  const { port, server } = await startServer({});
  const stream = await sockets.connect('127.0.0.1', port, 5000);
  const c = await SshClient.connect(stream, crypto, {
    auth: auth(), verifyHostKey: async () => true, keepaliveMs: 100, onBanner: () => {}
  });
  await new Promise((res) => setTimeout(res, 700));
  check(!c.isClosed, 'stays connected while keepalives are answered');
  let closedWith = '';
  c.onClose((e) => (closedWith = e || 'closed'));
  server.close();
  c.close();
  await new Promise((res) => setTimeout(res, 100));
  check(closedWith.length > 0, 'close is reported');
}

async function connectErrors(): Promise<void> {
  console.log('Connection errors');
  const plain = net.createServer((s) => s.end('HTTP/1.1 400 Bad Request\r\n\r\n'.repeat(1000)));
  await new Promise<void>((res) => plain.listen(0, '127.0.0.1', () => res()));
  const port = (plain.address() as net.AddressInfo).port;
  await expectFail(connect(port, auth()), 'without speaking SSH', 'non-SSH server is reported');
  plain.close();
}

(async () => {
  await algorithmMatrix();
  await authAndHostKeys();
  await commandsAndShell();
  await sftp();
  await jumpHost();
  await keepalive();
  await connectErrors();
  fs.rmSync(sftpRoot, { recursive: true, force: true });
  console.log(failures === 0 ? '\nAll SSH tests passed.' : `\n${failures} SSH test(s) FAILED.`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
