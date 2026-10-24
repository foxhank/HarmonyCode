/** Pure path helpers (POSIX-style paths inside the app sandbox). */
export class PathUtil {
  static join(dir: string, name: string): string {
    if (name.length === 0) {
      return dir;
    }
    return dir.endsWith('/') ? dir + name : dir + '/' + name;
  }

  static baseName(path: string): string {
    const i = path.lastIndexOf('/');
    return i >= 0 ? path.substring(i + 1) : path;
  }

  static dirName(path: string): string {
    const i = path.lastIndexOf('/');
    return i > 0 ? path.substring(0, i) : '/';
  }

  /** Lower-case extension without the dot ('' if none). */
  static extension(path: string): string {
    const name = PathUtil.baseName(path);
    const i = name.lastIndexOf('.');
    return i > 0 ? name.substring(i + 1).toLowerCase() : '';
  }

  /** Path of `path` relative to `root` ('' for root itself). */
  static relative(root: string, path: string): string {
    if (path === root) {
      return '';
    }
    return path.startsWith(root + '/') ? path.substring(root.length + 1) : path;
  }

  static isInside(root: string, path: string): boolean {
    return path === root || path.startsWith(root + '/');
  }

  /** A simple file name: not empty, no separators, not '.' or '..'. */
  static isValidName(name: string): boolean {
    return name.length > 0 && name !== '.' && name !== '..' && name.indexOf('/') < 0 && name.indexOf('\\') < 0;
  }

  /** Resolves `input` against `cwd`, handling '.', '..', '~' (= home) and absolute paths. */
  static resolve(cwd: string, input: string, home: string): string {
    let base = cwd;
    let rest = input;
    if (rest === '~' || rest.startsWith('~/')) {
      base = home;
      rest = rest.substring(1);
    } else if (rest.startsWith('/')) {
      base = '';
    }
    const parts: string[] = base.length > 0 ? base.split('/') : [''];
    for (const seg of rest.split('/')) {
      if (seg.length === 0 || seg === '.') {
        continue;
      }
      if (seg === '..') {
        if (parts.length > 1) {
          parts.pop();
        }
      } else {
        parts.push(seg);
      }
    }
    const out = parts.join('/');
    return out.length > 0 ? out : '/';
  }
}
