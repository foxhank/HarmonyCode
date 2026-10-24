import { Strings } from '../../core/common/Strings';

/** Localized names for catalog entries (string keys: env_<id>_name, tpl_<id>_detail, ...). */
export class CatalogText {
  static envName(id: string): string {
    return Strings.get('env_' + id + '_name');
  }

  static envDetail(id: string): string {
    return Strings.get('env_' + id + '_detail');
  }

  static templateName(id: string): string {
    return Strings.get('tpl_' + id + '_name');
  }

  static templateDetail(id: string): string {
    return Strings.get('tpl_' + id + '_detail');
  }
}
