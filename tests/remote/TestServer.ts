// An ssh2-based SSH server for the tests: password, keyboard-interactive and public-key login, exec
// through bash, a terminal that echoes, SFTP rooted at a temp folder, and TCP tunnels.
import * as fs from 'fs';
import * as net from 'net';
import * as os from 'os';
import * as path from 'path';
import { spawn } from 'child_process';
import { SshKeys, UserKey } from '../../entry/src/main/ets/core/remote/ssh/SshKeys';
import { NodeSocketFactory, NodeSshCrypto } from './NodeSsh';

// eslint-disable-next-line @typescript-eslint/no-var-requires
export const ssh2 = require('ssh2');

export const crypto = new NodeSshCrypto();
export const sockets = new NodeSocketFactory();
export const USER = 'dev';
export const PASSWORD = 'secret-pw';
export const userKey: UserKey = SshKeys.generate(crypto, 'phone@harmonycode');
export const sftpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'hc-sftp-'));

export const hostKeys = {
  ed25519: ssh2.utils.generateKeyPairSync('ed25519').private,
  ecdsa: ssh2.utils.generateKeyPairSync('ecdsa', { bits: 256 }).private,
  rsa: ssh2.utils.generateKeyPairSync('rsa', { bits: 2048 }).private
};

export interface ServerOpts {
  /**
   * SFTP shows the real disk with Git Bash paths ("/c/Users/..."), the same paths exec'd commands
   * see, so the server behaves like one machine. Default: SFTP is rooted at a temp folder.
   */
  realDisk?: boolean;
  algorithms?: object;
  methods?: string[];
  hostKey?: string;
  onClient?: (c: any) => void;
}

/** Starts an ssh2 server on a free port. */
export function startServer(o: ServerOpts): Promise<{ port: number; server: any; resizes: number[][] }> {
  const allowed = ssh2.utils.parseKey(SshKeys.publicKeyLine(userKey));
  const methods = o.methods ?? ['password', 'publickey', 'keyboard-interactive'];
  const resizes: number[][] = [];
  const server = new ssh2.Server({ hostKeys: [o.hostKey ?? hostKeys.ed25519], algorithms: o.algorithms }, (client: any) => {
    o.onClient?.(client);
    client.on('authentication', (ctx: any) => {
      if (ctx.username !== USER || methods.indexOf(ctx.method) < 0) {
        return ctx.reject(methods);
      }
      if (ctx.method === 'password') {
        return ctx.password === PASSWORD ? ctx.accept() : ctx.reject(methods);
      }
      if (ctx.method === 'keyboard-interactive') {
        return ctx.prompt([{ prompt: 'Password: ', echo: false }], 'Login', 'Use your password',
          (answers: string[]) => (answers[0] === PASSWORD ? ctx.accept() : ctx.reject(methods)));
      }
      if (ctx.method === 'publickey') {
        if (ctx.key.algo !== allowed.type || Buffer.compare(ctx.key.data, allowed.getPublicSSH()) !== 0) {
          return ctx.reject(methods);
        }
        if (ctx.signature && allowed.verify(ctx.blob, ctx.signature, ctx.hashAlgo) !== true) {
          return ctx.reject(methods);
        }
        return ctx.accept();
      }
      ctx.reject(methods);
    });
    client.on('ready', () => {
      client.on('session', (accept: any) => {
        const session = accept();
        session.on('exec', (acc: any, _rej: any, info: any) => {
          const stream = acc();
          const env = { ...process.env, PATH: path.dirname(process.execPath) + path.delimiter + (process.env.PATH ?? '') };
          const child = spawn('bash', ['-c', info.command], { env: env });
          child.stdout.on('data', (d: Buffer) => stream.write(d));
          child.stderr.on('data', (d: Buffer) => stream.stderr.write(d));
          stream.on('data', (d: Buffer) => child.stdin.write(d));
          stream.on('end', () => child.stdin.end());
          child.on('close', (code: number) => {
            stream.exit(code ?? 255);
            stream.end();
          });
        });
        session.on('pty', (acc: any, _rej: any, info: any) => {
          resizes.push([info.cols, info.rows]);
          acc?.();
        });
        session.on('window-change', (acc: any, _rej: any, info: any) => {
          resizes.push([info.cols, info.rows]);
          acc?.();
        });
        session.on('shell', (acc: any) => {
          const stream = acc();
          stream.write('welcome\r\n$ ');
          stream.on('data', (d: Buffer) => {
            const s = d.toString();
            if (s.indexOf('exit') >= 0) {
              stream.exit(0);
              stream.end();
            } else {
              stream.write('echo:' + s);
            }
          });
        });
        session.on('sftp', (acc: any) => serveSftp(acc(), o.realDisk === true));
      });
      client.on('tcpip', (acc: any, _rej: any, info: any) => {
        const sock = net.connect(info.destPort, info.destIP, () => {
          const ch = acc();
          ch.pipe(sock).pipe(ch);
        });
      });
    });
    client.on('error', () => {});
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => resolve({ port: server.address().port, server, resizes }));
  });
}

/** Minimal SFTP server rooted at sftpRoot (virtual "/" = the root). */
function serveSftp(sftp: any, realDisk: boolean): void {
  const STATUS = ssh2.utils.sftp.STATUS_CODE;
  const OPEN = ssh2.utils.sftp.OPEN_MODE;
  const handles = new Map<number, { fd?: number; dir?: string[] }>();
  let next = 1;
  const home = '/' + os.homedir().replace(/\\/g, '/').replace(/^([A-Za-z]):/, (m: string, d: string) => d.toLowerCase());
  const real = (p: string): string => {
    if (!realDisk) {
      return path.join(sftpRoot, path.posix.normalize('/' + p));
    }
    const abs = path.posix.normalize(p.startsWith('/') ? p : home + '/' + p);
    const m = /^\/([a-zA-Z])(\/.*)?$/.exec(abs);
    return m ? m[1].toUpperCase() + ':' + (m[2] ?? '/') : abs;
  };
  const handleBuf = (n: number): Buffer => {
    const b = Buffer.alloc(4);
    b.writeUInt32BE(n);
    return b;
  };
  const attrsOf = (st: fs.Stats): object => ({
    mode: st.mode, uid: 0, gid: 0, size: st.size, atime: Math.floor(st.atimeMs / 1000), mtime: Math.floor(st.mtimeMs / 1000)
  });
  const fail = (id: number, e: any): void => sftp.status(id, e?.code === 'ENOENT' ? STATUS.NO_SUCH_FILE : STATUS.FAILURE, String(e?.message ?? e));
  sftp.on('REALPATH', (id: number, p: string) => {
    const norm = realDisk ? path.posix.normalize(p === '.' || p.length === 0 ? home : (p.startsWith('/') ? p : home + '/' + p)) :
      path.posix.normalize('/' + (p === '.' ? '' : p));
    sftp.name(id, [{ filename: norm, longname: norm, attrs: {} }]);
  });
  const stat = (id: number, p: string): void => {
    try {
      sftp.attrs(id, attrsOf(fs.statSync(real(p))));
    } catch (e) {
      fail(id, e);
    }
  };
  sftp.on('STAT', stat);
  sftp.on('LSTAT', stat);
  sftp.on('FSTAT', (id: number, h: Buffer) => {
    const e = handles.get(h.readUInt32BE(0));
    sftp.attrs(id, attrsOf(fs.fstatSync(e!.fd!)));
  });
  sftp.on('OPEN', (id: number, p: string, flags: number) => {
    try {
      let mode = 'r';
      if (flags & OPEN.WRITE) {
        mode = flags & OPEN.TRUNC ? 'w' : 'r+';
      }
      const fd = fs.openSync(real(p), mode);
      const n = next++;
      handles.set(n, { fd });
      sftp.handle(id, handleBuf(n));
    } catch (e) {
      fail(id, e);
    }
  });
  sftp.on('READ', (id: number, h: Buffer, offset: number, len: number) => {
    const e = handles.get(h.readUInt32BE(0))!;
    const buf = Buffer.alloc(len);
    const n = fs.readSync(e.fd!, buf, 0, len, offset);
    if (n === 0) {
      sftp.status(id, STATUS.EOF);
    } else {
      sftp.data(id, buf.subarray(0, n));
    }
  });
  sftp.on('WRITE', (id: number, h: Buffer, offset: number, data: Buffer) => {
    const e = handles.get(h.readUInt32BE(0))!;
    fs.writeSync(e.fd!, data, 0, data.length, offset);
    sftp.status(id, STATUS.OK);
  });
  sftp.on('CLOSE', (id: number, h: Buffer) => {
    const n = h.readUInt32BE(0);
    const e = handles.get(n);
    if (e?.fd !== undefined) {
      fs.closeSync(e.fd);
    }
    handles.delete(n);
    sftp.status(id, STATUS.OK);
  });
  sftp.on('OPENDIR', (id: number, p: string) => {
    try {
      const names = fs.readdirSync(real(p));
      const n = next++;
      handles.set(n, { dir: names.map((x) => path.join(real(p), x)) });
      sftp.handle(id, handleBuf(n));
    } catch (e) {
      fail(id, e);
    }
  });
  sftp.on('READDIR', (id: number, h: Buffer) => {
    const e = handles.get(h.readUInt32BE(0))!;
    if (!e.dir || e.dir.length === 0) {
      return sftp.status(id, STATUS.EOF);
    }
    const batch = e.dir.splice(0, 3); // several READDIR rounds
    sftp.name(id, batch.map((f) => ({ filename: path.basename(f), longname: path.basename(f), attrs: attrsOf(fs.statSync(f)) })));
  });
  const simple = (fn: (id: number, ...a: any[]) => void) => (id: number, ...a: any[]) => {
    try {
      fn(id, ...a);
      sftp.status(id, STATUS.OK);
    } catch (e) {
      fail(id, e);
    }
  };
  sftp.on('MKDIR', simple((_id, p: string) => fs.mkdirSync(real(p))));
  sftp.on('RMDIR', simple((_id, p: string) => fs.rmdirSync(real(p))));
  sftp.on('REMOVE', simple((_id, p: string) => fs.unlinkSync(real(p))));
  sftp.on('RENAME', simple((_id, a: string, b: string) => fs.renameSync(real(a), real(b))));
}

