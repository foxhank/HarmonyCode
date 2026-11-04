import { formatBytes } from '../../core/common/ByteFormat';
import { Strings } from '../../core/common/Strings';
import { envImages, ImageStatus } from '../../core/env/EnvImages';
import { EnvironmentDef, ImageSource } from '../../core/project/Catalog';

const PERCENT: number = 100;

/** Localized names for catalog entries (string keys: env_<id>_name, tpl_<id>_detail, ...). */
export class CatalogText {
  static envName(id: string): string {
    return Strings.get('env_' + id + '_name');
  }

  static envDetail(id: string): string {
    return Strings.get('env_' + id + '_detail');
  }

  /** Install state of a VM environment, e.g. 'Installed · 1.2 GB' or 'Downloading 42%'; '' for others. */
  static envStatus(env: EnvironmentDef): string {
    if (!env.isVm || env.image === undefined) {
      return '';
    }
    const s = envImages.state(env.id);
    const pct = Math.floor(s.progress * PERCENT) + '%';
    const bundled = env.image.source === ImageSource.BUNDLED;
    if (s.status === ImageStatus.INSTALLED) {
      return Strings.get('env_status_installed', formatBytes(s.diskBytes));
    }
    if (s.status === ImageStatus.INSTALLING) {
      return Strings.get(bundled ? 'env_status_preparing' : 'env_status_downloading', pct);
    }
    if (s.status === ImageStatus.VERIFYING) {
      return Strings.get('env_status_verifying', pct);
    }
    return bundled ? Strings.get('env_status_bundled') :
      Strings.get('env_status_download', formatBytes(envImages.installBytes(env)));
  }

  static templateName(id: string): string {
    return Strings.get('tpl_' + id + '_name');
  }

  static templateDetail(id: string): string {
    return Strings.get('tpl_' + id + '_detail');
  }
}
