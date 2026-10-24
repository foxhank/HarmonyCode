import { i18n, intl } from '@kit.LocalizationKit';

const SECOND: number = 1000;
const MINUTE: number = 60 * SECOND;
const HOUR: number = 60 * MINUTE;
const DAY: number = 24 * HOUR;
const WEEK: number = 7 * DAY;
const MONTH: number = 30 * DAY;
const YEAR: number = 365 * DAY;

/** Locale-aware "3 hours ago" / "yesterday" style times. */
export class TimeFormat {
  static relative(timestampMs: number, nowMs: number = Date.now()): string {
    const diff = timestampMs - nowMs;
    const abs = Math.abs(diff);
    const fmt = new intl.RelativeTimeFormat(i18n.System.getAppPreferredLanguage(), { numeric: 'auto' });
    if (abs < MINUTE) {
      return fmt.format(0, 'second');
    }
    if (abs < HOUR) {
      return fmt.format(Math.round(diff / MINUTE), 'minute');
    }
    if (abs < DAY) {
      return fmt.format(Math.round(diff / HOUR), 'hour');
    }
    if (abs < WEEK) {
      return fmt.format(Math.round(diff / DAY), 'day');
    }
    if (abs < MONTH) {
      return fmt.format(Math.round(diff / WEEK), 'week');
    }
    if (abs < YEAR) {
      return fmt.format(Math.round(diff / MONTH), 'month');
    }
    return fmt.format(Math.round(diff / YEAR), 'year');
  }

  /** Locale-aware date + time. */
  static dateTime(timestampMs: number): string {
    const fmt = new intl.DateTimeFormat(i18n.System.getAppPreferredLanguage(), { dateStyle: 'medium', timeStyle: 'short' });
    return fmt.format(new Date(timestampMs));
  }
}
