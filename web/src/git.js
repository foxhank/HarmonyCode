// Git engine for HarmonyCode: isomorphic-git running inside an ArkTS worker,
// with a file-system adapter over @ohos.file.fs and an HTTP adapter over
// @ohos.net.http. Exposes a small, typed API (see ets/vendor/igit.d.ts).
import fs from '@ohos.file.fs';
import http from '@ohos.net.http';
import * as git from 'isomorphic-git';
import { utf8Encode, utf8Decode } from './git-shims.js';

// ---------- file system adapter ----------

function fsError(e, path) {
  const msg = String((e && e.message) || e);
  const code = e && e.code;
  let errno = 'EIO';
  if (code === 13900002 || /no such file/i.test(msg)) errno = 'ENOENT';
  else if (code === 13900015 || /file exists/i.test(msg)) errno = 'EEXIST';
  else if (code === 13900018 || /not a directory/i.test(msg)) errno = 'ENOTDIR';
  else if (code === 13900019 || /is a directory/i.test(msg)) errno = 'EISDIR';
  else if (/not empty/i.test(msg)) errno = 'ENOTEMPTY';
  const err = new Error(`${errno}: ${msg}, ${path}`);
  err.code = errno;
  return err;
}

function wrap(path, fn) {
  try { return Promise.resolve(fn()); } catch (e) { return Promise.reject(fsError(e, path)); }
}

function toStat(st) {
  const isDir = st.isDirectory();
  const isLink = typeof st.isSymbolicLink === 'function' && st.isSymbolicLink();
  return {
    type: isDir ? 'dir' : (isLink ? 'symlink' : 'file'),
    mode: st.mode,
    size: st.size,
    ino: Number(st.ino || 0),
    mtimeMs: st.mtime * 1000,
    ctimeMs: st.ctime * 1000,
    uid: st.uid || 1,
    gid: st.gid || 1,
    dev: 1,
    isFile: () => !isDir && !isLink,
    isDirectory: () => isDir,
    isSymbolicLink: () => isLink,
  };
}

function readAll(path) {
  const st = fs.statSync(path);
  if (st.isDirectory()) { const e = new Error('Is a directory'); throw e; }
  const total = st.size;
  const out = new Uint8Array(total);
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    let pos = 0;
    while (pos < total) {
      const chunk = new ArrayBuffer(Math.min(total - pos, 1 << 20));
      const n = fs.readSync(file.fd, chunk, { offset: pos });
      if (n <= 0) break;
      out.set(new Uint8Array(chunk, 0, n), pos);
      pos += n;
    }
    return pos === total ? out : out.subarray(0, pos);
  } finally {
    fs.closeSync(file);
  }
}

function writeAll(path, data) {
  const u8 = typeof data === 'string' ? utf8Encode(data) : (data instanceof Uint8Array ? data : new Uint8Array(data));
  const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    if (u8.byteLength > 0) {
      const ab = u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength);
      let pos = 0;
      while (pos < ab.byteLength) {
        const n = fs.writeSync(file.fd, ab.slice(pos), { offset: pos });
        if (n <= 0) break;
        pos += n;
      }
    }
  } finally {
    fs.closeSync(file);
  }
}

const promises = {
  readFile(path, opts) {
    const enc = typeof opts === 'string' ? opts : opts && opts.encoding;
    return wrap(path, () => {
      const u8 = readAll(path);
      return enc === 'utf8' || enc === 'utf-8' ? utf8Decode(u8) : u8;
    });
  },
  writeFile(path, data) { return wrap(path, () => writeAll(path, data)); },
  unlink(path) { return wrap(path, () => fs.unlinkSync(path)); },
  readdir(path) { return wrap(path, () => fs.listFileSync(path)); },
  mkdir(path) { return wrap(path, () => fs.mkdirSync(path)); },
  rmdir(path) {
    return wrap(path, () => {
      if (fs.listFileSync(path).length > 0) throw new Error('Directory not empty');
      fs.rmdirSync(path);
    });
  },
  stat(path) { return wrap(path, () => toStat(fs.statSync(path))); },
  lstat(path) { return wrap(path, () => toStat(fs.lstatSync ? fs.lstatSync(path) : fs.statSync(path))); },
  readlink(path) {
    return wrap(path, () => {
      if (typeof fs.readlinkSync === 'function') return fs.readlinkSync(path);
      throw new Error('No such file or directory');
    });
  },
  symlink(target, path) {
    return wrap(path, () => {
      if (typeof fs.symlinkSync === 'function') return fs.symlinkSync(target, path);
      return writeAll(path, target); // fallback: store link target as a file
    });
  },
  chmod() { return Promise.resolve(); },
};
const gfs = { promises };

// ---------- HTTP adapter ----------

async function collect(body) {
  if (!body) return undefined;
  const parts = [];
  let len = 0;
  for await (const chunk of body) { parts.push(chunk); len += chunk.byteLength; }
  const out = new Uint8Array(len);
  let off = 0;
  for (const p of parts) { out.set(p, off); off += p.byteLength; }
  return out.buffer;
}

const ghttp = {
  async request({ url, method = 'GET', headers = {}, body }) {
    const data = await collect(body);
    const req = http.createHttp();
    const chunks = [];
    let respHeaders = {};
    try {
      const options = {
        method: method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: Object.assign({ 'user-agent': 'git/isomorphic-git (HarmonyCode)' }, headers),
        connectTimeout: 30000,
        readTimeout: 300000,
        usingCache: false,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
      };
      if (data) options.extraData = data;
      let status;
      if (typeof req.requestInStream === 'function') {
        req.on('headersReceive', (h) => { respHeaders = h || {}; });
        req.on('dataReceive', (ab) => { chunks.push(new Uint8Array(ab)); });
        status = await req.requestInStream(url, options);
      } else {
        options.maxLimit = 100 * 1024 * 1024;
        const res = await req.request(url, options);
        status = res.responseCode;
        respHeaders = res.header || {};
        chunks.push(new Uint8Array(res.result));
      }
      const lower = {};
      for (const k of Object.keys(respHeaders)) lower[k.toLowerCase()] = String(respHeaders[k]);
      return { url, method, statusCode: status, statusMessage: String(status), headers: lower, body: chunks };
    } finally {
      try { req.off('headersReceive'); req.off('dataReceive'); } catch (e) { /* ignore */ }
      req.destroy();
    }
  },
};

// ---------- public API ----------

function authFor(auth) {
  if (!auth || !auth.token) return undefined;
  return () => ({ username: auth.username || 'git', password: auth.token });
}
const onAuthFailure = () => ({ cancel: true });

export async function gitIsRepo(dir) {
  try { await git.findRoot({ fs: gfs, filepath: dir }); return true; } catch (e) { return false; }
}

export async function gitInit(dir, defaultBranch) {
  await git.init({ fs: gfs, dir, defaultBranch: defaultBranch || 'main' });
}

export async function gitStatus(dir) {
  const rows = await git.statusMatrix({ fs: gfs, dir, cache: {} });
  const out = [];
  for (const [path, head, workdir, stage] of rows) {
    if (head === 1 && workdir === 1 && stage === 1) continue; // unchanged
    out.push({ path, head, workdir, stage });
  }
  return out;
}

export async function gitStage(dir, filepath) {
  const rows = await git.statusMatrix({ fs: gfs, dir, filepaths: [filepath] });
  const row = rows.find((r) => r[0] === filepath);
  if (row && row[2] === 0) await git.remove({ fs: gfs, dir, filepath });
  else await git.add({ fs: gfs, dir, filepath });
}

export async function gitStageAll(dir) {
  const rows = await git.statusMatrix({ fs: gfs, dir, cache: {} });
  for (const [filepath, , workdir, stage] of rows) {
    if (workdir === stage) continue;
    if (workdir === 0) await git.remove({ fs: gfs, dir, filepath });
    else await git.add({ fs: gfs, dir, filepath });
  }
}

export async function gitUnstage(dir, filepath) {
  await git.resetIndex({ fs: gfs, dir, filepath });
}

export async function gitDiscard(dir, filepath) {
  let tracked = true;
  try {
    const head = await git.resolveRef({ fs: gfs, dir, ref: 'HEAD' });
    await git.readBlob({ fs: gfs, dir, oid: head, filepath });
  } catch (e) { tracked = false; }
  if (tracked) {
    await git.checkout({ fs: gfs, dir, filepaths: [filepath], force: true });
  } else {
    try { await git.remove({ fs: gfs, dir, filepath }); } catch (e) { /* not staged */ }
    try { fs.unlinkSync(dir + '/' + filepath); } catch (e) { /* already gone */ }
  }
}

export async function gitCommit(dir, message, name, email) {
  return git.commit({ fs: gfs, dir, message, author: { name: name || 'HarmonyCode User', email: email || 'user@harmonycode.local' } });
}

export async function gitLog(dir, depth) {
  try {
    const commits = await git.log({ fs: gfs, dir, depth: depth || 50 });
    return commits.map((c) => ({
      oid: c.oid,
      message: c.commit.message,
      authorName: c.commit.author.name,
      authorEmail: c.commit.author.email,
      timestamp: c.commit.author.timestamp,
    }));
  } catch (e) {
    return []; // no commits yet
  }
}

export async function gitBranches(dir) {
  const current = (await git.currentBranch({ fs: gfs, dir, fullname: false })) || '';
  const local = await git.listBranches({ fs: gfs, dir });
  let remote = [];
  try { remote = (await git.listBranches({ fs: gfs, dir, remote: 'origin' })).filter((b) => b !== 'HEAD'); } catch (e) { /* no remote */ }
  return { current, local, remote };
}

export async function gitCreateBranch(dir, name, checkout) {
  await git.branch({ fs: gfs, dir, ref: name, checkout: !!checkout });
}

export async function gitCheckout(dir, ref) {
  await git.checkout({ fs: gfs, dir, ref });
}

export async function gitReadHead(dir, filepath) {
  try {
    const oid = await git.resolveRef({ fs: gfs, dir, ref: 'HEAD' });
    const { blob } = await git.readBlob({ fs: gfs, dir, oid, filepath });
    return utf8Decode(blob);
  } catch (e) {
    return '';
  }
}

export async function gitRemotes(dir) {
  return (await git.listRemotes({ fs: gfs, dir })).map((r) => ({ remote: r.remote, url: r.url }));
}

export async function gitSetRemote(dir, remote, url) {
  try { await git.deleteRemote({ fs: gfs, dir, remote }); } catch (e) { /* none yet */ }
  await git.addRemote({ fs: gfs, dir, remote, url });
}

function progress(cb) {
  return cb ? (e) => cb(e.phase || '', e.loaded || 0, e.total || 0) : undefined;
}

export async function gitClone(dir, url, auth, onProgress) {
  await git.clone({
    fs: gfs, http: ghttp, dir, url, singleBranch: true, depth: 50,
    onAuth: authFor(auth), onAuthFailure, onProgress: progress(onProgress), cache: {},
  });
}

export async function gitFetch(dir, auth, onProgress) {
  const res = await git.fetch({ fs: gfs, http: ghttp, dir, remote: 'origin', onAuth: authFor(auth), onAuthFailure, onProgress: progress(onProgress) });
  return res.fetchHead || '';
}

export async function gitPull(dir, auth, name, email, onProgress) {
  const ref = (await git.currentBranch({ fs: gfs, dir, fullname: false })) || 'main';
  await git.pull({
    fs: gfs, http: ghttp, dir, ref, remote: 'origin', singleBranch: true,
    author: { name: name || 'HarmonyCode User', email: email || 'user@harmonycode.local' },
    onAuth: authFor(auth), onAuthFailure, onProgress: progress(onProgress),
  });
}

export async function gitPush(dir, auth, onProgress) {
  const ref = (await git.currentBranch({ fs: gfs, dir, fullname: false })) || 'main';
  const res = await git.push({ fs: gfs, http: ghttp, dir, remote: 'origin', ref, onAuth: authFor(auth), onAuthFailure, onProgress: progress(onProgress) });
  if (res && res.ok === false) throw new Error(res.error || 'push rejected');
}
