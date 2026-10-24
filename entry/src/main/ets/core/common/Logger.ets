import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x4843; // "HC"
const PREFIX: string = 'HarmonyCode';

export class Logger {
  static info(tag: string, msg: string): void {
    hilog.info(DOMAIN, PREFIX, '[%{public}s] %{public}s', tag, msg);
  }

  static warn(tag: string, msg: string): void {
    hilog.warn(DOMAIN, PREFIX, '[%{public}s] %{public}s', tag, msg);
  }

  static error(tag: string, msg: string): void {
    hilog.error(DOMAIN, PREFIX, '[%{public}s] %{public}s', tag, msg);
  }
}

/** Message text from anything thrown. */
export function errorMessage(e: Object | undefined | null): string {
  if (e === undefined || e === null) {
    return '';
  }
  if (e instanceof Error) {
    return e.message;
  }
  return String(e);
}
