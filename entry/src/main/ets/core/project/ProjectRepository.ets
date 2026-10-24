import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppConfig } from '../common/AppConfig';
import { AppPaths } from '../common/AppPaths';
import { Logger, errorMessage } from '../common/Logger';
import { FileService } from '../fs/FileService';
import { PathUtil } from '../fs/PathUtil';
import { ProjectInfo, copyProject } from './ProjectInfo';

const KEY_LIST: string = 'list';

/** The persisted list of known projects, most recently opened first. */
@ObservedV2
export class ProjectRepository {
  @Trace projects: ProjectInfo[] = [];
  private prefs: preferences.Preferences | null = null;

  load(ctx: common.Context): void {
    this.prefs = preferences.getPreferencesSync(ctx, { name: AppConfig.PREFS_PROJECTS });
    try {
      const list = JSON.parse(this.prefs.getSync(KEY_LIST, '[]') as string) as ProjectInfo[];
      this.projects = ProjectRepository.sorted(list.filter((p: ProjectInfo) => FileService.exists(p.path)));
    } catch (e) {
      Logger.error('ProjectRepository', errorMessage(e as Error));
      this.projects = [];
    }
  }

  get(id: string): ProjectInfo | undefined {
    return this.projects.find((p: ProjectInfo) => p.id === id);
  }

  /** Workspace folders that aren't in the list yet (e.g. created from the terminal). */
  unlistedFolders(): string[] {
    const known = new Set<string>(this.projects.map((p: ProjectInfo) => p.path));
    return FileService.list(AppPaths.workspace, false)
      .filter((e) => e.isDir && !known.has(e.path))
      .map((e) => e.path);
  }

  add(name: string, path: string, envId: string, templateId: string, runCommand: string): ProjectInfo {
    const now = Date.now();
    const p: ProjectInfo = {
      id: now.toString(36) + Math.floor(Math.random() * 1e9).toString(36),
      name: name, path: path, envId: envId, templateId: templateId, runCommand: runCommand,
      createdAt: now, lastOpened: now
    };
    this.projects = [p].concat(this.projects);
    this.persist();
    return p;
  }

  update(p: ProjectInfo): void {
    this.projects = ProjectRepository.sorted(this.projects.map((x: ProjectInfo) => x.id === p.id ? p : x));
    this.persist();
  }

  markOpened(id: string): void {
    const p = this.get(id);
    if (p !== undefined) {
      const c = copyProject(p);
      c.lastOpened = Date.now();
      this.update(c);
    }
  }

  /** Removes from the list; with deleteFiles, also deletes the folder (only inside the workspace). */
  remove(id: string, deleteFiles: boolean): void {
    const p = this.get(id);
    if (p !== undefined && deleteFiles && PathUtil.isInside(AppPaths.workspace, p.path) &&
      p.path !== AppPaths.workspace) {
      FileService.remove(p.path);
    }
    this.projects = this.projects.filter((x: ProjectInfo) => x.id !== id);
    this.persist();
  }

  private persist(): void {
    if (this.prefs !== null) {
      this.prefs.putSync(KEY_LIST, JSON.stringify(this.projects));
      this.prefs.flush();
    }
  }

  private static sorted(list: ProjectInfo[]): ProjectInfo[] {
    return list.slice().sort((a: ProjectInfo, b: ProjectInfo) => b.lastOpened - a.lastOpened);
  }
}

export const projectRepository: ProjectRepository = new ProjectRepository();
