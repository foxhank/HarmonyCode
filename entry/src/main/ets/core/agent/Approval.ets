import { ToolKind, ToolLabel } from './ToolTypes';

/** How much the agent may do without asking (Codex-style modes). */
export class ApprovalMode {
  /** Ask before editing files, running commands and fetching web pages. */
  static readonly ASK: string = 'ask';
  /** Edit files and fetch pages freely; ask before running commands. */
  static readonly AUTO_EDIT: string = 'auto_edit';
  /** Never ask. */
  static readonly FULL_AUTO: string = 'full_auto';

  static all(): string[] {
    return [ApprovalMode.ASK, ApprovalMode.AUTO_EDIT, ApprovalMode.FULL_AUTO];
  }
}

export class ApprovalDecision {
  static readonly APPROVE: string = 'approve';
  /** Approve, and stop asking for this kind of action (or this command) for the rest of the session. */
  static readonly APPROVE_ALWAYS: string = 'approve_always';
  static readonly DENY: string = 'deny';
}

/** What the user is asked to approve. */
export interface ApprovalRequest {
  callId: string;
  toolName: string;
  kind: string;
  label: ToolLabel;
  /** Diff or command line. */
  preview: string;
  /** For commands: the prefix "approve always" would allow, e.g. "npm test" ('' = the whole kind). */
  ruleKey: string;
}

export interface ApprovalReply {
  decision: string;
  /** Optional instructions from the user when denying ("use pytest instead"). */
  feedback: string;
}

/** Asks the user. The UI resolves the promise when they answer. */
export interface ApprovalGate {
  request(req: ApprovalRequest): Promise<ApprovalReply>;
}

/** Tools whose first argument is a sub-command worth keeping in a rule ("git status", "npm test"). */
const TWO_WORD_TOOLS: string[] = ['git', 'npm', 'pnpm', 'yarn', 'npx', 'bun', 'cargo', 'go', 'pip', 'pip3', 'uv',
  'poetry', 'docker', 'kubectl', 'make', 'gradle', './gradlew', 'mvn', 'dotnet', 'apk', 'apt', 'apt-get', 'brew',
  'systemctl', 'ohpm', 'hvigorw', 'flutter', 'deno', 'composer', 'bundle', 'rails', 'python', 'python3', 'node'];
/** Shell syntax that chains or substitutes commands: such lines never match a rule. */
const COMPOUND: RegExp = new RegExp('[;&|`\\n]|\\$\\(|>|<');

/** Decides which tool calls need the user's approval. */
export class ApprovalPolicy {
  mode: string;
  private alwaysAllowed: Set<string> = new Set();
  private allowedCommands: Set<string> = new Set();

  constructor(mode: string) {
    this.mode = mode;
  }

  /** The rule a command line falls under ('' when it cannot be covered by a rule). */
  static commandKey(command: string): string {
    const c = command.trim();
    if (c.length === 0 || COMPOUND.test(c)) {
      return '';
    }
    const words = c.split(new RegExp('\\s+')).filter((w: string) => !w.includes('='));
    if (words.length === 0) {
      return '';
    }
    if (TWO_WORD_TOOLS.indexOf(words[0]) >= 0 && words.length > 1 && !words[1].startsWith('-')) {
      return words[0] + ' ' + words[1];
    }
    return words[0];
  }

  needsApproval(kind: string, ruleKey: string): boolean {
    if (kind === ToolKind.READ || kind === ToolKind.META || this.mode === ApprovalMode.FULL_AUTO) {
      return false;
    }
    if (this.alwaysAllowed.has(kind)) {
      return false;
    }
    if (kind === ToolKind.EXECUTE && ruleKey.length > 0 && this.allowedCommands.has(ruleKey)) {
      return false;
    }
    if (this.mode === ApprovalMode.AUTO_EDIT) {
      return kind === ToolKind.EXECUTE;
    }
    return true;
  }

  allowAlways(kind: string, ruleKey: string): void {
    if (kind === ToolKind.EXECUTE && ruleKey.length > 0) {
      this.allowedCommands.add(ruleKey);
    } else {
      this.alwaysAllowed.add(kind);
    }
  }

  reset(): void {
    this.alwaysAllowed.clear();
    this.allowedCommands.clear();
  }
}
