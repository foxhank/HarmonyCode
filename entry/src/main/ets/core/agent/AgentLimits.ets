/** Numbers that bound what the agent does in one turn and how much it sends to the model. */
export class AgentLimits {
  /** Model calls per user message before the agent stops and asks to continue. */
  static readonly MAX_STEPS_DEFAULT: number = 50;
  static readonly MAX_STEPS_MIN: number = 5;
  static readonly MAX_STEPS_MAX: number = 200;
  /** Characters of a single tool result sent to the model. */
  static readonly MAX_TOOL_OUTPUT_CHARS: number = 30000;
  /** read_file defaults. */
  static readonly READ_DEFAULT_LINES: number = 2000;
  static readonly READ_MAX_LINE_CHARS: number = 2000;
  /** list_dir / glob / grep caps. */
  static readonly LIST_MAX_ENTRIES: number = 400;
  static readonly LIST_MAX_DEPTH: number = 4;
  static readonly WALK_MAX_FILES: number = 20000;
  static readonly GLOB_MAX_RESULTS: number = 200;
  static readonly GREP_MAX_MATCHES: number = 200;
  static readonly GREP_MAX_FILE_BYTES: number = 1024 * 1024;
  static readonly GREP_MAX_CONTEXT: number = 5;
  /** run_command. */
  static readonly COMMAND_TIMEOUT_DEFAULT_MS: number = 120000;
  static readonly COMMAND_TIMEOUT_MAX_MS: number = 600000;
  /** Background jobs (run_in_background) are killed after this long. */
  static readonly BACKGROUND_TIMEOUT_MS: number = 6 * 60 * 60 * 1000;
  /** How long run_command waits for early output of a background job. */
  static readonly BACKGROUND_FIRST_LOOK_MS: number = 1500;
  static readonly JOB_WAIT_MAX_MS: number = 60000;
  static readonly JOB_KILL_WAIT_MS: number = 2000;
  /** Web tools. */
  static readonly SEARCH_MAX_RESULTS: number = 20;
  static readonly FETCH_PART_CHARS: number = 20000;
  /** Sub-agents (task tool). */
  static readonly SUBAGENT_MAX_STEPS: number = 30;
  /** Compact the conversation when it uses this share of the model's context window. */
  static readonly COMPACT_THRESHOLD: number = 0.8;
  /** Older tool results longer than this are replaced by a stub before compacting. */
  static readonly PRUNE_TOOL_OUTPUT_CHARS: number = 2000;
  /** The most recent turns whose tool results are never pruned. */
  static readonly PRUNE_KEEP_TURNS: number = 2;
  /** Rough characters per token, for estimates when the provider hasn't reported usage. */
  static readonly CHARS_PER_TOKEN: number = 4;
  /** Identical consecutive tool calls that trigger a "you are repeating yourself" warning. */
  static readonly REPEAT_WARN_COUNT: number = 3;
  /** Project instruction files read into the system prompt. */
  static readonly INSTRUCTION_FILES: string[] = ['AGENTS.md', 'CLAUDE.md', '.harmonycode/AGENTS.md'];
  static readonly INSTRUCTIONS_MAX_CHARS: number = 12000;
  /** Folders skipped by searches and listings. */
  static readonly IGNORED_DIRS: string[] = ['.git', 'node_modules', 'target', 'build', '.venv', 'venv',
    '__pycache__', 'oh_modules', '.hvigor', 'dist', '.idea', '.gradle', '.next', '.cache'];
}
