import { ChangeCode } from '../../core/git/GitTypes';

/** Color for a Git change code (explorer names, Source Control letters). */
export function gitColor(code: string): ResourceColor {
  switch (code) {
    case ChangeCode.MODIFIED:
      return $r('app.color.git_modified');
    case ChangeCode.ADDED:
      return $r('app.color.git_added');
    case ChangeCode.DELETED:
      return $r('app.color.git_deleted');
    case ChangeCode.UNTRACKED:
      return $r('app.color.git_untracked');
    default:
      return $r('app.color.text_primary');
  }
}
