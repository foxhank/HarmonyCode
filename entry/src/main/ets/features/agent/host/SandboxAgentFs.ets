import { AgentFs, FsEntry, FsStat } from '../../../core/agent/AgentFs';
import { FileService } from '../../../core/fs/FileService';

/** AgentFs over the app sandbox (FileService, which is synchronous and local). */
export class SandboxAgentFs implements AgentFs {
  async stat(path: string): Promise<FsStat | null> {
    if (!FileService.exists(path)) {
      return null;
    }
    const dir = FileService.isDir(path);
    return { isDir: dir, size: dir ? 0 : FileService.size(path) };
  }

  async list(dir: string): Promise<FsEntry[]> {
    return FileService.list(dir, true).map((e): FsEntry => {
      return { name: e.name, path: e.path, isDir: e.isDir, size: e.isDir ? 0 : FileService.size(e.path) };
    });
  }

  async readText(path: string): Promise<string> {
    return FileService.readText(path);
  }

  async writeText(path: string, text: string): Promise<void> {
    FileService.writeText(path, text);
  }

  async remove(path: string): Promise<void> {
    FileService.remove(path);
  }

  async mkdirs(path: string): Promise<void> {
    FileService.mkdirs(path);
  }

  async rename(from: string, to: string): Promise<void> {
    if (FileService.exists(to) && !FileService.isDir(to)) {
      FileService.remove(to);
    }
    FileService.rename(from, to);
  }
}
