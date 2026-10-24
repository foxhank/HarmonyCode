import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { Logger, errorMessage } from '../common/Logger';

const CATALOG_FILE: string = 'catalog/catalog.json';
const TEMPLATE_ROOT: string = 'catalog/templates/';

/** A Linux environment a project can run in. Display text: env_<id>_name / env_<id>_detail strings. */
export interface EnvironmentDef {
  id: string;
  /** Runs in the hiSH Linux VM. */
  isVm: boolean;
  /** Package install command prefix, e.g. 'apk add'. */
  installCmd: string;
  available: boolean;
  recommended: boolean;
}

/** A starter project. Display text: tpl_<id>_name / tpl_<id>_detail strings. */
export interface TemplateDef {
  id: string;
  badge: string;
  color: string;
  /** Alpine package names, space-separated. */
  packages: string;
  runCommand: string;
  /** Paths under rawfile/catalog/templates/<id>/ ('gitignore' is written as '.gitignore'). */
  files: string[];
}

interface CatalogData {
  environments: EnvironmentDef[];
  templates: TemplateDef[];
  packageAliases: Record<string, Record<string, string>>;
}

/** Environments and project templates, loaded from rawfile/catalog. */
export class Catalog {
  private static data: CatalogData = { environments: [], templates: [], packageAliases: {} };
  private static ctx: common.Context | null = null;

  static load(ctx: common.Context): void {
    Catalog.ctx = ctx;
    try {
      Catalog.data = JSON.parse(Catalog.readRaw(CATALOG_FILE)) as CatalogData;
    } catch (e) {
      Logger.error('Catalog', errorMessage(e as Error));
    }
  }

  static environments(): EnvironmentDef[] {
    return Catalog.data.environments;
  }

  static templates(): TemplateDef[] {
    return Catalog.data.templates;
  }

  static environment(id: string): EnvironmentDef | undefined {
    return Catalog.data.environments.find((e: EnvironmentDef) => e.id === id);
  }

  static template(id: string): TemplateDef | undefined {
    return Catalog.data.templates.find((t: TemplateDef) => t.id === id);
  }

  static defaultEnvironment(): EnvironmentDef {
    const rec = Catalog.data.environments.find((e: EnvironmentDef) => e.recommended);
    return rec ?? Catalog.data.environments[0];
  }

  /** e.g. 'apk add python3 py3-pip' or 'apt install -y python3 python3-pip'; '' if nothing to install. */
  static installCommand(env: EnvironmentDef, tpl: TemplateDef): string {
    if (!env.isVm || tpl.packages.length === 0) {
      return '';
    }
    const family = env.installCmd.split(' ')[0];
    const aliases: Record<string, string> | undefined = Catalog.data.packageAliases[family];
    const out: string[] = [];
    for (const name of tpl.packages.split(' ')) {
      let mapped = name;
      if (aliases !== undefined && aliases[name] !== undefined) {
        mapped = aliases[name];
      }
      if (mapped.length > 0) {
        out.push(mapped);
      }
    }
    return env.installCmd + ' ' + out.join(' ');
  }

  /** Text content of one template file. */
  static templateFile(tpl: TemplateDef, file: string): string {
    return Catalog.readRaw(TEMPLATE_ROOT + tpl.id + '/' + file);
  }

  private static readRaw(path: string): string {
    const ctx = Catalog.ctx;
    if (ctx === null) {
      return '';
    }
    const bytes = ctx.resourceManager.getRawFileContentSync(path);
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  }
}
