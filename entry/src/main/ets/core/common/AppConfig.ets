/**
 * Behavioural limits and identifiers in one place. Visual values (colors, sizes, text)
 * live in resources/ instead; this file holds numbers the code computes with.
 */
export class AppConfig {
  // Breakpoints (vp). Below SM_MAX -> phone layout; below MD_MAX -> tablet layout; else desktop.
  static readonly BREAKPOINT_SM_MAX: number = 600;
  static readonly BREAKPOINT_MD_MAX: number = 1024;

  // Resizable panes (vp).
  static readonly SIDEBAR_DEFAULT: number = 260;
  static readonly SIDEBAR_MIN: number = 180;
  static readonly SIDEBAR_MAX: number = 520;
  static readonly PANEL_DEFAULT: number = 240;
  static readonly PANEL_MIN: number = 100;
  static readonly PANEL_MAX_RATIO: number = 0.8;

  // Files.
  static readonly MAX_TEXT_FILE_BYTES: number = 8 * 1024 * 1024;
  static readonly BINARY_PROBE_BYTES: number = 8000;
  static readonly IGNORED_DIRS: string[] = ['.git', 'node_modules', 'target', 'build', '.venv', '__pycache__',
    'oh_modules', '.hvigor', 'dist'];

  // Search & quick open.
  static readonly SEARCH_MAX_FILES: number = 5000;
  static readonly SEARCH_MAX_FILE_BYTES: number = 1024 * 1024;
  static readonly SEARCH_MAX_RESULTS: number = 500;
  static readonly SEARCH_PREVIEW_LEAD: number = 30;
  static readonly SEARCH_PREVIEW_LEN: number = 160;
  static readonly QUICK_OPEN_MAX_FILES: number = 20000;
  static readonly QUICK_OPEN_MAX_RESULTS: number = 50;

  // Timing (ms).
  static readonly AUTO_SAVE_DELAY: number = 1000;
  static readonly GIT_REFRESH_DEBOUNCE: number = 600;
  static readonly TOAST_DURATION: number = 2600;

  // Git.
  static readonly GIT_DEFAULT_BRANCH: string = 'main';
  static readonly GIT_LOG_DEPTH: number = 50;
  static readonly GIT_WORKER_PATH: string = 'entry/ets/workers/GitWorker.ets';
  static readonly GIT_FALLBACK_NAME: string = 'HarmonyCode User';
  static readonly GIT_FALLBACK_EMAIL: string = 'user@harmonycode.local';

  // Terminal.
  static readonly TERMINAL_SCROLLBACK_CHARS: number = 200000;
  static readonly TERMINAL_HISTORY_SIZE: number = 200;

  // Editor defaults (user-adjustable in Settings).
  static readonly EDITOR_FONT_DEFAULT: number = 14;
  static readonly EDITOR_FONT_MIN: number = 10;
  static readonly EDITOR_FONT_MAX: number = 28;
  static readonly TAB_SIZE_DEFAULT: number = 4;
  static readonly TERMINAL_FONT_DEFAULT: number = 13;

  // Web views (paths inside resources/rawfile).
  static readonly EDITOR_PAGE: string = 'web/editor.html';
  static readonly TERMINAL_PAGE: string = 'web/terminal.html';

  // Linux VM (hiSH).
  static readonly VM_CPUS_DEFAULT: number = 2;
  static readonly VM_CPUS_MIN: number = 1;
  static readonly VM_CPUS_MAX: number = 8;
  static readonly VM_MEMORY_DEFAULT_MB: number = 1024;
  static readonly VM_MEMORY_MIN_MB: number = 512;
  static readonly VM_MEMORY_MAX_MB: number = 8192;
  static readonly VM_MEMORY_STEP_MB: number = 256;
  /** Guest ports reachable from the device at 127.0.0.1:<same port> (skipped if already taken). */
  static readonly VM_FORWARDED_PORTS: number[] = [3000, 5000, 8000, 8080];
  /** Where the workspace appears inside the VM (hiSH images mount the share there). */
  static readonly VM_GUEST_SHARE: string = '/mnt/share';
  /** Output kept while no terminal is attached to the VM. */
  static readonly VM_BACKLOG_CHARS: number = 200000;
  /** Console text examined for login and shell prompts. */
  static readonly VM_PROMPT_TAIL_CHARS: number = 256;
  static readonly VM_SOCKET_NAME: string = 'hish-console.sock';
  static readonly VM_ROOTFS_FILE: string = 'rootfs.qcow2';
  static readonly VM_WINSIZE_FILE: string = 'winsize';
  static readonly VM_PROGRESS_STEP: number = 0.01;
  static readonly VM_PROGRESS_INTERVAL: number = 250;

  // Folder names inside the app sandbox.
  static readonly WORKSPACE_DIR: string = 'workspace';
  static readonly VM_CONTROL_DIR: string = '.harmonycode';
  static readonly VM_DIR: string = 'vm';
  static readonly VM_FIRMWARE_DIR: string = 'firmware';

  // Preference store names.
  static readonly PREFS_SETTINGS: string = 'settings';
  static readonly PREFS_PROJECTS: string = 'projects';
  static readonly SECRET_GIT_TOKEN: string = 'harmonycode.git.token';
}
