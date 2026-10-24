// Builds the web bundles HarmonyCode ships:
//  - rawfile/web/editor.*   CodeMirror 6 editor, loaded in an ArkWeb view
//  - rawfile/web/terminal.* xterm.js terminal, loaded in an ArkWeb view
//  - ets/vendor/igit.js     isomorphic-git wrapper, run natively by the Git worker
import * as esbuild from 'esbuild';
import { copyFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const main = resolve(here, '../entry/src/main');
const rawWeb = resolve(main, 'resources/rawfile/web');
const vendor = resolve(main, 'ets/vendor');
mkdirSync(rawWeb, { recursive: true });
mkdirSync(vendor, { recursive: true });

await esbuild.build({
  entryPoints: { editor: 'src/editor.js', terminal: 'src/terminal.js' },
  outdir: rawWeb,
  bundle: true,
  minify: true,
  format: 'iife',
  target: 'chrome100',
  legalComments: 'none',
  absWorkingDir: here,
});

for (const f of ['editor.html', 'terminal.html']) {
  copyFileSync(resolve(here, 'src', f), resolve(rawWeb, f));
}

// The Git engine runs inside an ArkTS worker, not a browser, so it needs
// polyfills for Buffer / TextEncoder / process, and keeps @ohos imports external.
await esbuild.build({
  entryPoints: ['src/git.js'],
  outfile: resolve(vendor, 'igit.js'),
  bundle: true,
  minify: true,
  format: 'esm',
  platform: 'neutral',
  mainFields: ['module', 'main'],
  target: 'es2019',
  external: ['@ohos.file.fs', '@ohos.net.http'],
  inject: ['src/git-shims.js'],
  define: { 'process.env.NODE_ENV': '"production"' },
  legalComments: 'none',
  absWorkingDir: here,
});

console.log('web bundles built');
