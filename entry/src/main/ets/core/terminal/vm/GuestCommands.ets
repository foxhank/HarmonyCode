import { AppConfig } from '../../common/AppConfig';
import { AppPaths } from '../../common/AppPaths';
import { Strings } from '../../common/Strings';
import { PathUtil } from '../../fs/PathUtil';
import { Catalog, EnvironmentDef } from '../../project/Catalog';
import { ProjectInfo } from '../../project/ProjectInfo';

/** Packages a project needs, installed once per environment. */
export interface PackageSetup {
  /** File created in the guest after a successful install, so it runs once. */
  marker: string;
  command: string;
  message: string;
}

/** Where a project lives inside the VM and what it needs there. */
export interface GuestProject {
  /** '' when the project is outside the shared workspace. */
  dir: string;
  setup: PackageSetup | null;
}

const MARKER_DIR: string = '/var/lib/harmonycode';
const QUOTE: RegExp = new RegExp('\'', 'g');

/** Shell command lines the IDE types into the VM. Plain POSIX sh, so they work in ash and bash. */
export class GuestCommands {
  static quote(s: string): string {
    return '\'' + s.replace(QUOTE, '\'\\\'\'') + '\'';
  }

  /** Guest path of a host path inside the workspace, or '' if it is outside. */
  static guestPath(hostPath: string): string {
    if (!PathUtil.isInside(AppPaths.workspace, hostPath)) {
      return '';
    }
    return AppConfig.VM_GUEST_SHARE + hostPath.substring(AppPaths.workspace.length);
  }

  static project(p: ProjectInfo, env: EnvironmentDef): GuestProject {
    const tpl = Catalog.template(p.templateId);
    const command = tpl !== undefined ? Catalog.installCommand(env, tpl) : '';
    const setup: PackageSetup | null = tpl === undefined || command.length === 0 ? null : {
      marker: MARKER_DIR + '/template-' + tpl.id,
      command: command,
      message: Strings.get('vm_installing_packages', command)
    };
    return { dir: GuestCommands.guestPath(p.path), setup: setup };
  }

  /**
   * Run once after login: before every prompt, apply the terminal size the IDE writes to the shared
   * winsize file (a serial console has no other way to learn it), and let git work in the shared
   * folder, whose files belong to the host user.
   */
  static init(): string {
    const ws = GuestCommands.quote(GuestCommands.guestPath(
      PathUtil.join(AppPaths.vmControl, AppConfig.VM_WINSIZE_FILE)));
    return `hc_ws() { [ -r ${ws} ] && stty $(cat ${ws}) 2>/dev/null; }; PS1='$(hc_ws)'"$PS1"; hc_ws; ` +
      `grep -qs 'directory = \\*' ~/.gitconfig || printf '[safe]\\n\\tdirectory = *\\n' >> ~/.gitconfig`;
  }

  /** Changes to the project folder, clears the screen, and installs the project's packages once. */
  static enter(project: GuestProject): string {
    let line = project.dir.length > 0 ? `cd ${GuestCommands.quote(project.dir)} && clear` : 'clear';
    const s = project.setup;
    if (s !== null) {
      const marker = GuestCommands.quote(s.marker);
      line += `; [ -f ${marker} ] || { echo ${GuestCommands.quote(s.message)}; ${s.command} && ` +
        `mkdir -p ${GuestCommands.quote(MARKER_DIR)} && touch ${marker}; }`;
    }
    return line;
  }

  /** Runs `cmd` from the project folder. */
  static inProject(project: GuestProject, cmd: string): string {
    return project.dir.length > 0 ? `cd ${GuestCommands.quote(project.dir)} && ${cmd}` : cmd;
  }

  /** Content of the winsize file. */
  static winsize(cols: number, rows: number): string {
    return `rows ${rows} cols ${cols}\n`;
  }
}
