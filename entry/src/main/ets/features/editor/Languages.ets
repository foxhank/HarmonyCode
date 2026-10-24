import { Strings } from '../../core/common/Strings';
import { PathUtil } from '../../core/fs/PathUtil';

/** Language names by extension. Names are product names (not translated); unknown -> "Plain Text". */
const NAMES: Map<string, string> = new Map<string, string>([
  ['js', 'JavaScript'], ['mjs', 'JavaScript'], ['cjs', 'JavaScript'], ['jsx', 'JavaScript React'],
  ['ts', 'TypeScript'], ['tsx', 'TypeScript React'], ['ets', 'ArkTS'], ['json', 'JSON'], ['json5', 'JSON5'],
  ['py', 'Python'], ['c', 'C'], ['h', 'C'], ['cc', 'C++'], ['cpp', 'C++'], ['cxx', 'C++'], ['hpp', 'C++'],
  ['java', 'Java'], ['kt', 'Kotlin'], ['rs', 'Rust'], ['go', 'Go'], ['md', 'Markdown'], ['html', 'HTML'],
  ['htm', 'HTML'], ['css', 'CSS'], ['scss', 'SCSS'], ['less', 'Less'], ['xml', 'XML'], ['svg', 'SVG'],
  ['yml', 'YAML'], ['yaml', 'YAML'], ['sql', 'SQL'], ['sh', 'Shell'], ['bash', 'Shell'], ['toml', 'TOML'],
  ['vue', 'Vue'],
]);

const FILE_NAMES: Map<string, string> = new Map<string, string>([
  ['makefile', 'Makefile'], ['dockerfile', 'Dockerfile'],
]);

export class Languages {
  static nameFor(path: string): string {
    const byName = FILE_NAMES.get(PathUtil.baseName(path).toLowerCase());
    if (byName !== undefined) {
      return byName;
    }
    return NAMES.get(PathUtil.extension(path)) ?? Strings.get('lang_plain_text');
  }
}
