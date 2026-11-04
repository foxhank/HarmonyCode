import { Strings } from '../../core/common/Strings';
import { envImages } from '../../core/env/EnvImages';
import { errorMessage, Logger } from '../../core/common/Logger';
import { PathUtil } from '../../core/fs/PathUtil';
import { Catalog, EnvironmentDef, TemplateDef } from '../../core/project/Catalog';
import { ProjectFactory } from '../../core/project/ProjectFactory';
import { ProjectRepository } from '../../core/project/ProjectRepository';
import { GitClient } from '../../core/git/GitClient';
import { openWorkbench } from '../app/AppNavigation';

/** Form state for "New Project". */
@ObservedV2
export class NewProjectModel {
  @Trace name: string = '';
  @Trace templateId: string = '';
  @Trace envId: string = '';
  @Trace initGit: boolean = true;
  @Trace busy: boolean = false;
  @Trace error: string = '';
  private repo: ProjectRepository;
  private git: GitClient;

  constructor(repo: ProjectRepository, git: GitClient) {
    this.repo = repo;
    this.git = git;
    const firstTemplate = Catalog.templates()[0];
    this.templateId = firstTemplate !== undefined ? firstTemplate.id : '';
    this.envId = Catalog.defaultEnvironment()?.id ?? '';
  }

  get templates(): TemplateDef[] {
    return Catalog.templates();
  }

  get environments(): EnvironmentDef[] {
    return Catalog.environments();
  }

  @Computed
  get folderPreview(): string {
    return this.name.trim().length > 0 ? PathUtil.baseName(ProjectFactory.freeFolder(this.name)) : '';
  }

  @Computed
  get installPreview(): string {
    const env = Catalog.environment(this.envId);
    const tpl = Catalog.template(this.templateId);
    return env !== undefined && tpl !== undefined ? Catalog.installCommand(env, tpl) : '';
  }

  @Computed
  get canCreate(): boolean {
    return !this.busy && this.name.trim().length > 0;
  }

  selectTemplate(id: string): void {
    this.templateId = id;
  }

  selectEnvironment(env: EnvironmentDef): void {
    this.envId = env.id;
  }

  async create(): Promise<void> {
    const name = this.name.trim();
    const tpl = Catalog.template(this.templateId);
    if (name.length === 0 || tpl === undefined) {
      this.error = Strings.get('new_error_name_required');
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      const dir = ProjectFactory.freeFolder(name);
      ProjectFactory.writeTemplate(dir, name, tpl);
      if (this.initGit) {
        await this.git.init(dir);
      }
      const p = this.repo.add(name, dir, this.envId, tpl.id, tpl.runCommand);
      envImages.installInBackground(this.envId);
      openWorkbench(p.id);
    } catch (e) {
      const msg = errorMessage(e as Error);
      Logger.error('NewProject', msg);
      this.error = Strings.get('new_error_failed', msg);
    } finally {
      this.busy = false;
    }
  }
}
