// Bundles a test (which imports the app's .ets sources as TypeScript) and runs it with Node.
//   node build.mjs <test-name> [args...]     e.g. node build.mjs llm C:\path\to\account.txt
import { build } from '../../web/node_modules/esbuild/lib/main.js';
import { spawnSync } from 'child_process';
import { fileURLToPath } from 'url';
import * as path from 'path';
import * as os from 'os';

const here = path.dirname(fileURLToPath(import.meta.url));
const name = process.argv[2];
const out = path.join(os.tmpdir(), `harmonycode-${name}.test.cjs`);
await build({
  entryPoints: [path.join(here, `${name}.test.ts`)],
  bundle: true,
  platform: 'node',
  format: 'cjs',
  target: 'node18',
  outfile: out,
  loader: { '.ets': 'ts' },
  resolveExtensions: ['.ts', '.ets', '.js'],
  logLevel: 'warning'
});
const r = spawnSync(process.execPath, [out, ...process.argv.slice(3)], { stdio: 'inherit' });
process.exit(r.status ?? 1);
