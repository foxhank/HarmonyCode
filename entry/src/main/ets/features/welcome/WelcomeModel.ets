import { Strings } from '../../core/common/Strings';
import { errorMessage } from '../../core/common/Logger';
import { PathUtil } from '../../core/fs/PathUtil';
import { Catalog } from '../../core/project/Catalog';
import { ProjectInfo } from '../../core/project/ProjectInfo';
import { ProjectRepository } from '../../core/project/ProjectRepository';
import { Buttons } from '../dialogs/Buttons';
import { ButtonRole, DIALOG_CANCELLED, DialogModel } from '../dialogs/DialogModel';
import { ToastModel } from '../dialogs/ToastModel';
import { openWorkbench } from '../app/AppNavigation';

const NO_ENV: string = 'none';
const EMPTY_TEMPLATE: string = 'empty';

/** State and actions for the welcome screen. */
@ObservedV2
export class WelcomeModel {
  @Trace filter: string = '';
  @Trace showOpenSheet: boolean = false;
  @Trace openCandidates: string[] = [];
  private repo: ProjectRepository;
  private dialogs: DialogModel;
  private toasts: ToastModel;

  constructor(repo: ProjectRepository, dialogs: DialogModel, toasts: ToastModel) {
    this.repo = repo;
    this.dialogs = dialogs;
    this.toasts = toasts;
  }

  @Computed
  get visibleProjects(): ProjectInfo[] {
    const f = this.filter.trim().toLowerCase();
    if (f.length === 0) {
      return this.repo.projects;
    }
    return this.repo.projects.filter((p: ProjectInfo) => p.name.toLowerCase().indexOf(f) >= 0);
  }

  get hasProjects(): boolean {
    return this.repo.projects.length > 0;
  }

  open(p: ProjectInfo): void {
    this.repo.markOpened(p.id);
    openWorkbench(p.id);
  }

  /** Shows workspace folders that aren't in the list yet. */
  showOpen(): void {
    this.openCandidates = this.repo.unlistedFolders();
    this.showOpenSheet = true;
  }

  openFolder(path: string): void {
    this.showOpenSheet = false;
    const env = Catalog.defaultEnvironment();
    const p = this.repo.add(PathUtil.baseName(path), path, env !== undefined ? env.id : NO_ENV, EMPTY_TEMPLATE, '');
    this.open(p);
  }

  async remove(p: ProjectInfo): Promise<void> {
    const choice = await this.dialogs.confirm(
      Strings.get('welcome_remove_title'), Strings.get('welcome_remove_message', p.name),
      [Buttons.cancel(), Buttons.of($r('app.string.action_remove'), ButtonRole.PRIMARY)]);
    if (choice === 1) {
      this.repo.remove(p.id, false);
    }
  }

  async deleteFromDisk(p: ProjectInfo): Promise<void> {
    const choice = await this.dialogs.confirm(
      Strings.get('welcome_delete_title'), Strings.get('welcome_delete_message', p.name),
      [Buttons.cancel(), Buttons.del()]);
    if (choice === DIALOG_CANCELLED || choice === 0) {
      return;
    }
    try {
      this.repo.remove(p.id, true);
      this.toasts.info(Strings.get('welcome_deleted', p.name));
    } catch (e) {
      this.toasts.error(errorMessage(e as Error));
    }
  }
}
