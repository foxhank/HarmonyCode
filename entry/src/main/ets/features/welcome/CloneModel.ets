import { Strings } from '../../core/common/Strings';
import { envImages } from '../../core/env/EnvImages';
import { errorMessage, Logger } from '../../core/common/Logger';
import { FileService } from '../../core/fs/FileService';
import { Catalog, EnvironmentDef } from '../../core/project/Catalog';
import { ProjectFactory } from '../../core/project/ProjectFactory';
import { ProjectRepository } from '../../core/project/ProjectRepository';
import { GitClient } from '../../core/git/GitClient';
import { openWorkbench } from '../app/AppNavigation';

const EMPTY_TEMPLATE: string = 'empty';
const URL_PATTERN: RegExp = new RegExp('^(https?://)[^\\s]+$');

/** Form state for "Get from Version Control". */
@ObservedV2
export class CloneModel {
  @Trace url: string = '';
  @Trace name: string = '';
  @Trace envId: string = '';
  @Trace busy: boolean = false;
  @Trace phase: string = '';
  @Trace progress: number = 0;
  @Trace error: string = '';
  private nameEdited: boolean = false;
  private repo: ProjectRepository;
  private git: GitClient;

  constructor(repo: ProjectRepository, git: GitClient) {
    this.repo = repo;
    this.git = git;
    this.envId = Catalog.defaultEnvironment()?.id ?? '';
  }

  get environments(): EnvironmentDef[] {
    return Catalog.environments();
  }

  @Computed
  get canClone(): boolean {
    return !this.busy && URL_PATTERN.test(this.url.trim()) && this.name.trim().length > 0;
  }

  setUrl(url: string): void {
    this.url = url;
    if (!this.nameEdited) {
      this.name = ProjectFactory.nameFromUrl(url);
    }
  }

  setName(name: string): void {
    this.name = name;
    this.nameEdited = name.length > 0;
  }

  selectEnvironment(env: EnvironmentDef): void {
    this.envId = env.id;
  }

  async clone(): Promise<void> {
    if (!this.canClone) {
      this.error = Strings.get('clone_error_url');
      return;
    }
    const name = this.name.trim();
    const dir = ProjectFactory.freeFolder(name);
    this.busy = true;
    this.error = '';
    this.progress = 0;
    try {
      FileService.mkdirs(dir);
      await this.git.clone(dir, this.url.trim(), (phase: string, loaded: number, total: number) => {
        this.phase = phase;
        this.progress = total > 0 ? loaded / total : 0;
      });
      const p = this.repo.add(name, dir, this.envId, EMPTY_TEMPLATE, '');
      envImages.installInBackground(this.envId);
      openWorkbench(p.id);
    } catch (e) {
      const msg = errorMessage(e as Error);
      Logger.error('Clone', msg);
      this.error = Strings.get('clone_error_failed', msg);
      try {
        FileService.remove(dir);
      } catch (cleanupError) {
        Logger.warn('Clone', errorMessage(cleanupError as Error));
      }
    } finally {
      this.busy = false;
    }
  }
}
