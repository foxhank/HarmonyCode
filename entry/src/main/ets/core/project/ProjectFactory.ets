import { AppPaths } from '../common/AppPaths';
import { FileService } from '../fs/FileService';
import { PathUtil } from '../fs/PathUtil';
import { Catalog, TemplateDef } from './Catalog';

const DOTFILES: string[] = ['gitignore'];

/** Creates project folders on disk (from templates, or empty for clones). */
export class ProjectFactory {
  /** Folder/package-safe slug for a display name. */
  static slugify(name: string): string {
    const s = name.trim().toLowerCase()
      .replace(new RegExp('[^a-z0-9._-]+', 'g'), '-')
      .replace(new RegExp('^-+|-+$', 'g'), '');
    return s.length > 0 ? s : 'project';
  }

  /** A free folder path in the workspace for `name` (adds -2, -3... if taken). */
  static freeFolder(name: string): string {
    const base = ProjectFactory.slugify(name);
    let dir = PathUtil.join(AppPaths.workspace, base);
    let i = 2;
    while (FileService.exists(dir)) {
      dir = PathUtil.join(AppPaths.workspace, base + '-' + i);
      i++;
    }
    return dir;
  }

  /** Project name suggested by a clone URL ('https://x/y/repo.git' -> 'repo'). */
  static nameFromUrl(url: string): string {
    const trimmed = url.trim().replace(new RegExp('/+$'), '').replace(new RegExp('\\.git$'), '');
    const i = Math.max(trimmed.lastIndexOf('/'), trimmed.lastIndexOf(':'));
    return i >= 0 ? trimmed.substring(i + 1) : trimmed;
  }

  /** Writes the template's files into `dir`, filling in {{name}} and {{slug}}. */
  static writeTemplate(dir: string, name: string, tpl: TemplateDef): void {
    FileService.mkdirs(dir);
    const slug = ProjectFactory.slugify(name);
    for (const file of tpl.files) {
      const content = Catalog.templateFile(tpl, file)
        .replace(new RegExp('\\{\\{name\\}\\}', 'g'), name)
        .replace(new RegExp('\\{\\{slug\\}\\}', 'g'), slug);
      const target = DOTFILES.indexOf(PathUtil.baseName(file)) >= 0 ?
        PathUtil.join(PathUtil.dirName(PathUtil.join(dir, file)), '.' + PathUtil.baseName(file)) :
        PathUtil.join(dir, file);
      FileService.writeText(target, content);
    }
  }
}
