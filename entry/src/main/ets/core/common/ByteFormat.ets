const KB: number = 1024;
const MB: number = KB * 1024;
const GB: number = MB * 1024;
const ONE_DECIMAL: number = 10;

/** Short human-readable size: '850 KB', '434 MB', '1.2 GB'. */
export function formatBytes(bytes: number): string {
  if (bytes >= GB) {
    return (Math.round(bytes / GB * ONE_DECIMAL) / ONE_DECIMAL) + ' GB';
  }
  if (bytes >= MB) {
    return Math.round(bytes / MB) + ' MB';
  }
  return Math.max(1, Math.round(bytes / KB)) + ' KB';
}
