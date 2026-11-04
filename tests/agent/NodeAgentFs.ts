// AgentFs and CommandRunner over Node (tests only). Paths use forward slashes like the app.
import * as fs from 'fs';
import { spawn } from 'child_process';
import * as path from 'path';
import { AgentFs, FsEntry, FsStat } from '../../entry/src/main/ets/core/agent/AgentFs';
import { CommandResult, CommandRunner, OutputListener } from '../../entry/src/main/ets/core/agent/CommandRunner';
import { CancelToken } from '../../entry/src/main/ets/core/llm/CancelToken';

export class NodeAgentFs implements AgentFs {
  async stat(path: string): Promise<FsStat | null> {
    try {
      const st = fs.statSync(path);
      return { isDir: st.isDirectory(), size: st.isDirectory() ? 0 : st.size };
    } catch (e) {
      return null;
    }
  }

  private isDir(path: string): boolean {
    try {
      return fs.statSync(path).isDirectory();
    } catch (e) {
      return false;
    }
  }

  private size(path: string): number {
    try {
      return fs.statSync(path).size;
    } catch (e) {
      return 0;
    }
  }

  async list(dir: string): Promise<FsEntry[]> {
    const out: FsEntry[] = fs.readdirSync(dir).filter((n) => n !== '.git').map((n) => {
      const p = dir + '/' + n;
      const isDir = this.isDir(p);
      return { name: n, path: p, isDir: isDir, size: isDir ? 0 : this.size(p) };
    });
    out.sort((a, b) => (a.isDir !== b.isDir ? (a.isDir ? -1 : 1) : a.name.toLowerCase().localeCompare(b.name.toLowerCase())));
    return out;
  }

  async readText(path: string): Promise<string> {
    const buf = fs.readFileSync(path);
    if (buf.subarray(0, 8000).includes(0)) {
      throw new Error('binary file');
    }
    return buf.toString('utf-8');
  }

  async writeText(path: string, text: string): Promise<void> {
    fs.mkdirSync(path.substring(0, path.lastIndexOf('/')), { recursive: true });
    fs.writeFileSync(path, text, 'utf-8');
  }

  async remove(path: string): Promise<void> {
    fs.rmSync(path, { recursive: true, force: true });
  }

  async mkdirs(path: string): Promise<void> {
    fs.mkdirSync(path, { recursive: true });
  }

  async rename(from: string, to: string): Promise<void> {
    fs.renameSync(from, to);
  }
}

/** Runs commands with bash (Git Bash on Windows). */
export class NodeCommandRunner implements CommandRunner {
  describe(): string {
    return 'bash on the developer machine; node is installed.';
  }

  run(command: string, cwd: string, timeoutMs: number, cancel: CancelToken, onOutput: OutputListener): Promise<CommandResult> {
    return new Promise<CommandResult>((resolve) => {
      // Make the node running the tests available to the agent's commands.
      const env = { ...process.env, PATH: path.dirname(process.execPath) + path.delimiter + (process.env.PATH ?? '') };
      const child = spawn('bash', ['-c', command], { cwd: cwd, env: env });
      let output = '';
      let timedOut = false;
      let settled = false;
      const finish = (code: number): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        off();
        resolve({ exitCode: code, output: output, timedOut: timedOut });
      };
      // Killing bash on Windows leaves its children running; kill the whole tree.
      const killTree = (): void => {
        if (process.platform === 'win32' && child.pid !== undefined) {
          spawn('taskkill', ['/pid', String(child.pid), '/T', '/F']);
        } else {
          child.kill('SIGKILL');
        }
      };
      const take = (b: Buffer): void => {
        const s = b.toString('utf-8');
        output += s;
        onOutput(s);
      };
      child.stdout.on('data', take);
      child.stderr.on('data', take);
      const timer = setTimeout(() => {
        timedOut = true;
        killTree();
        finish(-1);
      }, timeoutMs);
      const off = cancel.onCancel(() => {
        killTree();
        finish(-1);
      });
      child.on('close', (code) => finish(code === null ? -1 : code));
    });
  }
}
