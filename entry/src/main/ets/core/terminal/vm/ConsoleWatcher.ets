import { AppConfig } from '../../common/AppConfig';
import { LoginStep } from '../../project/Catalog';

/** What the console output asks for. */
export interface ConsoleSignal {
  /** Text to type (a login answer), or ''. */
  reply: string;
  /** True when the console just arrived at a shell prompt. */
  prompt: boolean;
}

const ANSI: RegExp = new RegExp('\\x1b\\[[0-9;?]*[ -/]*[@-~]|\\x1b\\][^\\x07\\x1b]*(\\x07|\\x1b\\\\)|\\x1b[()][0-9A-Za-z]|\\x1b[=>78]', 'g');
const CR: RegExp = new RegExp('\\r', 'g');
/** A shell prompt: the output ends with '# ' (root) or '$ ' (user). */
const PROMPT: RegExp = new RegExp('[#$] $');

/**
 * Reads the VM console the way a person would: answers login prompts from the environment's
 * login steps, and notices when a shell prompt is waiting for input.
 */
export class ConsoleWatcher {
  private tail: string = '';
  private steps: LoginStep[];
  private nextStep: number = 0;
  private atPrompt: boolean = false;

  constructor(steps: LoginStep[]) {
    this.steps = steps;
  }

  feed(text: string): ConsoleSignal {
    this.tail = (this.tail + text.replace(ANSI, '').replace(CR, '')).slice(-AppConfig.VM_PROMPT_TAIL_CHARS);
    const signal: ConsoleSignal = { reply: '', prompt: false };
    if (this.nextStep < this.steps.length) {
      const step = this.steps[this.nextStep];
      if (this.tail.trimEnd().endsWith(step.expect)) {
        this.nextStep++;
        this.tail = '';
        signal.reply = step.send + '\r';
        return signal;
      }
    }
    const waiting = PROMPT.test(this.tail);
    signal.prompt = waiting && !this.atPrompt;
    this.atPrompt = waiting;
    return signal;
  }

  /** True while the shell is idle at a prompt (no input typed since it appeared). */
  idleAtPrompt(): boolean {
    return this.atPrompt;
  }

  /** Something was typed, so the shell is no longer idle. */
  inputSent(): void {
    this.atPrompt = false;
    this.tail = '';
  }
}
