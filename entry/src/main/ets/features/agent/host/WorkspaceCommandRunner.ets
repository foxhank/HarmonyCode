import { CommandResult, CommandRunner, OutputListener } from '../../../core/agent/CommandRunner';
import { CancelToken } from '../../../core/llm/CancelToken';

/**
 * Uses the Linux VM when the project's terminal runs on it, else the built-in shell. Decided per
 * call, so the agent follows the VM as it starts.
 */
export class WorkspaceCommandRunner implements CommandRunner {
  private vm: CommandRunner;
  private builtin: CommandRunner;
  private usesVm: () => boolean;

  constructor(vm: CommandRunner, builtin: CommandRunner, usesVm: () => boolean) {
    this.vm = vm;
    this.builtin = builtin;
    this.usesVm = usesVm;
  }

  describe(): string {
    return this.current().describe();
  }

  run(command: string, cwd: string, timeoutMs: number, cancel: CancelToken, onOutput: OutputListener): Promise<CommandResult> {
    return this.current().run(command, cwd, timeoutMs, cancel, onOutput);
  }

  private current(): CommandRunner {
    return this.usesVm() ? this.vm : this.builtin;
  }
}
