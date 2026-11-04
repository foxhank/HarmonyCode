import { CancelToken } from '../llm/CancelToken';
import { Json, JsonObject } from '../llm/Json';
import { ToolSpec } from '../llm/LlmTypes';
import { AgentFs } from './AgentFs';
import { BackgroundJobs } from './BackgroundJobs';
import { CommandRunner } from './CommandRunner';
import { SubagentRunner, UserPrompter } from './Interaction';
import { PathGuard } from './PathGuard';
import { PlanStep } from './PlanTypes';
import { ReadTracker } from './ReadTracker';
import { ToolInputError } from './ToolErrors';
import { WebAccess } from './web/WebAccess';

export { ToolInputError } from './ToolErrors';

/** What a tool does, which decides whether it needs the user's approval. */
export class ToolKind {
  /** Only looks (read, list, search). Never asks; may run in parallel with other reads. */
  static readonly READ: string = 'read';
  /** Changes files. */
  static readonly EDIT: string = 'edit';
  /** Runs commands. */
  static readonly EXECUTE: string = 'execute';
  /** Fetches arbitrary URLs from the internet. */
  static readonly NETWORK: string = 'network';
  /** Bookkeeping or talking to the user (plans, questions, sub-agents). Never asks. */
  static readonly META: string = 'meta';
}

/** Typed access to a tool call's JSON arguments. */
export class ToolArgs {
  readonly raw: JsonObject;

  constructor(raw: JsonObject) {
    this.raw = raw;
  }

  static parse(json: string): ToolArgs {
    const text = json.trim().length === 0 ? '{}' : json;
    const o = Json.parseObject(text);
    if (o === null) {
      throw new ToolInputError('Arguments are not a valid JSON object: ' + text.substring(0, 200));
    }
    return new ToolArgs(o);
  }

  has(name: string): boolean {
    return Json.has(this.raw, name);
  }

  /** A required string (may be empty only when `allowEmpty`). */
  str(name: string, allowEmpty: boolean = false): string {
    const v = Json.value(this.raw, name);
    if (typeof v !== 'string') {
      throw new ToolInputError(`Missing required string argument "${name}".`);
    }
    const s = v as string;
    if (!allowEmpty && s.length === 0) {
      throw new ToolInputError(`Argument "${name}" must not be empty.`);
    }
    return s;
  }

  optStr(name: string, fallback: string): string {
    return Json.str(this.raw, name, fallback);
  }

  optNum(name: string, fallback: number): number {
    const v = Json.value(this.raw, name);
    if (typeof v === 'number') {
      return v as number;
    }
    // Models sometimes send numbers as strings.
    if (typeof v === 'string' && (v as string).trim().length > 0 && !Number.isNaN(Number(v))) {
      return Number(v);
    }
    return fallback;
  }

  optBool(name: string, fallback: boolean): boolean {
    const v = Json.value(this.raw, name);
    if (typeof v === 'boolean') {
      return v as boolean;
    }
    if (typeof v === 'string') {
      return (v as string) === 'true';
    }
    return fallback;
  }

  objects(name: string): JsonObject[] {
    return Json.objects(this.raw, name);
  }

  /** A list of strings; also accepts a single string. */
  strings(name: string): string[] {
    const v = Json.value(this.raw, name);
    if (typeof v === 'string') {
      return [v as string];
    }
    if (Array.isArray(v)) {
      const out: string[] = [];
      for (const x of v as Object[]) {
        if (typeof x === 'string') {
          out.push(x as string);
        }
      }
      return out;
    }
    return [];
  }
}

/** Result of running a tool. */
export class ToolOutput {
  /** What the model sees. */
  text: string;
  isError: boolean;
  /** Extra detail for the UI (a diff, full command output); '' = show `text`. */
  display: string = '';
  /** Files the tool changed (absolute paths), so the IDE can refresh them. */
  changedFiles: string[] = [];

  constructor(text: string, isError: boolean) {
    this.text = text;
    this.isError = isError;
  }

  static ok(text: string): ToolOutput {
    return new ToolOutput(text, false);
  }

  static error(text: string): ToolOutput {
    return new ToolOutput(text, true);
  }
}

/** Short description of a call for the UI: a string-resource name for the verb plus a target. */
export interface ToolLabel {
  /** Name of a string resource such as 'agent_tool_read'. */
  verbKey: string;
  /** Path, pattern or command the call is about. */
  target: string;
}

/** Side effects tools report to the IDE. */
export interface ToolHost {
  planUpdated(steps: PlanStep[], explanation: string): void;
  /** Live output of a running command or sub-agent. */
  commandOutput(callId: string, chunk: string): void;
}

/** Everything a tool may use. Paths given by the model go through `paths`. */
export interface ToolContext {
  paths: PathGuard;
  fs: AgentFs;
  shell: CommandRunner;
  cancel: CancelToken;
  reads: ReadTracker;
  host: ToolHost;
  callId: string;
  prompter: UserPrompter;
  jobs: BackgroundJobs;
  /** null when web tools are not available. */
  web: WebAccess | null;
  /** null inside a sub-agent (no nesting). */
  subagents: SubagentRunner | null;
}

/** A capability offered to the model. */
export interface AgentTool {
  readonly spec: ToolSpec;
  readonly kind: string;
  label(args: ToolArgs): ToolLabel;
  /** What the user reviews before approving (a diff for edits, the command line for shells). */
  preview(args: ToolArgs, ctx: ToolContext): Promise<string>;
  run(args: ToolArgs, ctx: ToolContext): Promise<ToolOutput>;
}
