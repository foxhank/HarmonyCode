import { CancelToken } from '../llm/CancelToken';
import { ChatModel } from '../llm/ChatModel';
import { ChatMessage, LlmRequest, LlmStreamListener, MessagePart, Role, StopReason, TokenUsage } from '../llm/LlmTypes';
import { AgentListener, NoticeKind, ToolCallStatus, ToolCallView, TurnStatus } from './AgentEvents';
import { AgentFs } from './AgentFs';
import { AgentLimits } from './AgentLimits';
import { ApprovalDecision, ApprovalGate, ApprovalMode, ApprovalPolicy, ApprovalReply, ApprovalRequest } from './Approval';
import { BackgroundJobs } from './BackgroundJobs';
import { CommandRunner } from './CommandRunner';
import { ContextManager } from './ContextManager';
import { NoUserPrompter, ProgressListener, SubagentRunner, UserPrompter } from './Interaction';
import { PathGuard } from './PathGuard';
import { PlanStep } from './PlanTypes';
import { ReadTracker } from './ReadTracker';
import { AgentEnvironment, SystemPrompt } from './SystemPrompt';
import { ToolRegistry } from './ToolRegistry';
import { AgentTool, ToolArgs, ToolContext, ToolHost, ToolInputError, ToolKind, ToolLabel, ToolOutput } from './ToolTypes';
import { TextLimits } from './util/TextLimits';
import { WebAccess } from './web/WebAccess';

/** What an AgentSession is built from. Everything platform-specific comes in through these. */
export interface AgentDeps {
  model: ChatModel;
  fs: AgentFs;
  shell: CommandRunner;
  paths: PathGuard;
  tools: ToolRegistry;
  policy: ApprovalPolicy;
  gate: ApprovalGate;
  prompter: UserPrompter;
  jobs: BackgroundJobs;
  /** null = no web tools. */
  web: WebAccess | null;
  env: AgentEnvironment;
  maxSteps: number;
  /** NaN = model default. */
  temperature: number;
  /** False for sub-agents (they cannot start their own). */
  allowSubagents: boolean;
}

const CANCELLED_RESULT: string = 'Cancelled by the user before this tool ran.';
const SKIPPED_RESULT: string = 'Skipped: the user denied an earlier action in this step.';
const STEER_HEADER: string = '[The user sent this message while you were working:]\n';

/** Why a batch of tool calls stopped early. */
class BatchState {
  /** The user denied an action without feedback: end the turn and wait for them. */
  halted: boolean = false;
}

/** Forwards model stream deltas to the agent listener. */
class StreamForwarder implements LlmStreamListener {
  private listener: AgentListener;

  constructor(listener: AgentListener) {
    this.listener = listener;
  }

  onTextDelta(text: string): void {
    this.listener.onTextDelta(text);
  }

  onReasoningDelta(text: string): void {
    this.listener.onReasoningDelta(text);
  }

  onToolCallStart(callId: string, toolName: string): void {
    // Calls are announced once complete, with their arguments (see runTools).
  }
}

/** Sub-agents may not ask; nothing they run needs approval anyway. */
class DenyGate implements ApprovalGate {
  request(req: ApprovalRequest): Promise<ApprovalReply> {
    const r: ApprovalReply = { decision: ApprovalDecision.DENY, feedback: 'Sub-agents cannot ask for approval.' };
    return Promise.resolve(r);
  }
}

/** Turns a sub-agent's events into progress lines for the parent's tool card. */
class SubagentListener implements AgentListener {
  status: string = '';
  error: string = '';
  private progress: ProgressListener;

  constructor(progress: ProgressListener) {
    this.progress = progress;
  }

  onTurnStart(): void {
  }

  onStepStart(step: number): void {
  }

  onTextDelta(text: string): void {
  }

  onReasoningDelta(text: string): void {
  }

  onToolCall(call: ToolCallView): void {
    const target = call.label.target.length > 0 ? ' ' + TextLimits.line(call.label.target, 120) : '';
    this.progress('• ' + call.toolName + target);
  }

  onToolStatus(callId: string, status: string): void {
  }

  onToolOutput(callId: string, output: ToolOutput): void {
  }

  onCommandOutput(callId: string, chunk: string): void {
  }

  onPlan(steps: PlanStep[], explanation: string): void {
  }

  onUsage(usage: TokenUsage, contextTokens: number, contextWindow: number): void {
  }

  onNotice(kind: string, detail: string): void {
  }

  onFilesChanged(paths: string[]): void {
  }

  onTurnEnd(status: string, error: string): void {
    this.status = status;
    this.error = error;
  }
}

/**
 * A ReAct agent: each step the model reasons and either answers or calls tools; tool results
 * are fed back and the loop continues until it answers, hits the step limit, or is stopped.
 * Read-only calls of one step run in parallel; messages the user sends meanwhile are fed in
 * with the next tool results. Owns the conversation history; knows nothing about UI or wire formats.
 */
export class AgentSession implements ToolHost, SubagentRunner {
  private deps: AgentDeps;
  private listener: AgentListener;
  private history: ChatMessage[] = [];
  private reads: ReadTracker = new ReadTracker();
  private cancel: CancelToken | null = null;
  private lastContextTokens: number = 0;
  private lastCallKey: string = '';
  private repeatCount: number = 0;
  private steering: string[] = [];

  constructor(deps: AgentDeps, listener: AgentListener) {
    this.deps = deps;
    this.listener = listener;
  }

  get busy(): boolean {
    return this.cancel !== null;
  }

  get model(): ChatModel {
    return this.deps.model;
  }

  /** Switches model or limits between turns. */
  configure(model: ChatModel, maxSteps: number, temperature: number, approvalMode: string, customInstructions: string): void {
    this.deps.model = model;
    this.deps.maxSteps = maxSteps;
    this.deps.temperature = temperature;
    this.deps.policy.mode = approvalMode;
    this.deps.env.customInstructions = customInstructions;
  }

  /** Turns the web tools on (with the given client) or off; takes effect from the next turn. */
  setWeb(web: WebAccess | null): void {
    if ((web === null) === (this.deps.web === null)) {
      this.deps.web = web;
      return;
    }
    this.deps.web = web;
    this.deps.tools = ToolRegistry.coding(web !== null);
    this.deps.env.web = web !== null;
  }

  /** The conversation, for saving. */
  messages(): ChatMessage[] {
    return this.history.slice();
  }

  /** Restores a saved conversation. */
  restore(messages: ChatMessage[]): void {
    this.history = messages.slice();
    this.lastContextTokens = 0;
    this.reads.clear();
  }

  /** Starts a fresh conversation; stops background jobs. */
  reset(): void {
    this.stop();
    this.history = [];
    this.steering = [];
    this.reads.clear();
    this.lastContextTokens = 0;
    this.deps.policy.reset();
    this.deps.jobs.clear();
  }

  stop(): void {
    if (this.cancel !== null) {
      this.cancel.cancel();
    }
  }

  /** Stops everything, including background jobs. */
  dispose(): void {
    this.stop();
    this.deps.jobs.killAll();
  }

  /**
   * A message typed while the agent works. It is given to the model with the next tool results.
   * Returns false when no turn is running (send it as a normal message instead).
   */
  steer(text: string): boolean {
    if (this.cancel === null || text.trim().length === 0) {
      return false;
    }
    this.steering.push(text.trim());
    return true;
  }

  /** Runs one turn for `text`. Resolves when the turn ends; never rejects (errors go to onTurnEnd). */
  async send(text: string): Promise<void> {
    if (this.cancel !== null) {
      return;
    }
    const cancel = new CancelToken();
    this.cancel = cancel;
    this.history.push(ChatMessage.user(text));
    this.listener.onTurnStart();
    let status = TurnStatus.DONE;
    let error = '';
    try {
      status = await this.loop(cancel);
    } catch (e) {
      if (CancelToken.isCancellation(e as Error) || cancel.cancelled) {
        status = TurnStatus.CANCELLED;
      } else {
        status = TurnStatus.ERROR;
        error = (e as Error).message;
      }
    } finally {
      this.cancel = null;
    }
    // Messages that arrived after the last model call are not lost: they start the next turn's context.
    if (this.steering.length > 0) {
      this.history.push(ChatMessage.user(this.takeSteering()));
    }
    this.listener.onTurnEnd(status, error);
  }

  // ---------- ToolHost ----------

  planUpdated(steps: PlanStep[], explanation: string): void {
    this.listener.onPlan(steps, explanation);
  }

  commandOutput(callId: string, chunk: string): void {
    this.listener.onCommandOutput(callId, chunk);
  }

  // ---------- SubagentRunner ----------

  async runSubagent(prompt: string, onProgress: ProgressListener, cancel: CancelToken): Promise<string> {
    const d = this.deps;
    const fetchAllowed = d.web !== null && !d.policy.needsApproval(ToolKind.NETWORK, '');
    const env: AgentEnvironment = {
      kind: d.env.kind, projectName: d.env.projectName, root: d.env.root, shell: d.env.shell, today: d.env.today,
      customInstructions: d.env.customInstructions, web: d.web !== null, subagent: true
    };
    const listener = new SubagentListener(onProgress);
    const child = new AgentSession({
      model: d.model, fs: d.fs, shell: d.shell, paths: d.paths,
      tools: ToolRegistry.explore(d.web !== null, fetchAllowed),
      policy: new ApprovalPolicy(ApprovalMode.FULL_AUTO), gate: new DenyGate(), prompter: new NoUserPrompter(),
      jobs: d.jobs, web: d.web, env: env, maxSteps: AgentLimits.SUBAGENT_MAX_STEPS, temperature: d.temperature,
      allowSubagents: false
    }, listener);
    const off = cancel.onCancel(() => child.stop());
    try {
      await child.send(prompt);
    } finally {
      off();
    }
    cancel.throwIfCancelled();
    if (listener.status === TurnStatus.ERROR) {
      throw new Error('The sub-agent failed: ' + listener.error);
    }
    const msgs = child.messages();
    for (let i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role === Role.ASSISTANT && msgs[i].textContent().trim().length > 0) {
        const note = listener.status === TurnStatus.STEP_LIMIT ? '\n\n[The sub-agent hit its step limit; the report may be incomplete.]' : '';
        return msgs[i].textContent().trim() + note;
      }
    }
    return '';
  }

  // ---------- the loop ----------

  private async loop(cancel: CancelToken): Promise<string> {
    this.deps.env.shell = this.deps.shell.describe();
    const system = await SystemPrompt.build(this.deps.env, this.deps.fs, this.deps.paths);
    const tools = this.deps.tools.specs();
    for (let step = 1; step <= this.deps.maxSteps; step++) {
      cancel.throwIfCancelled();
      await this.fitContext(system, cancel);
      this.listener.onStepStart(step);
      const req = new LlmRequest();
      req.system = system;
      req.messages = this.history;
      req.tools = tools;
      req.temperature = this.deps.temperature;
      const result = await this.deps.model.complete(req, new StreamForwarder(this.listener), cancel);
      this.history.push(result.message);
      this.reportUsage(result.usage.inputTokens, result.usage.outputTokens, system);
      this.listener.onUsage(result.usage, this.lastContextTokens, this.deps.model.contextWindow);

      const calls = result.message.toolCalls();
      if (calls.length === 0) {
        if (this.steering.length > 0) {
          // The user added something while the model was answering: keep going with it.
          this.history.push(ChatMessage.user(this.takeSteering()));
          continue;
        }
        if (result.stopReason === StopReason.MAX_TOKENS) {
          this.listener.onNotice(NoticeKind.TRUNCATED, '');
        }
        return TurnStatus.DONE;
      }
      const state = new BatchState();
      const results = await this.runTools(calls, cancel, state);
      if (this.steering.length > 0 && !cancel.cancelled) {
        results.push(MessagePart.text(STEER_HEADER + this.takeSteering()));
      }
      this.history.push(new ChatMessage(Role.USER, results));
      if (cancel.cancelled) {
        return TurnStatus.CANCELLED;
      }
      if (state.halted) {
        return TurnStatus.DONE;
      }
    }
    return TurnStatus.STEP_LIMIT;
  }

  private takeSteering(): string {
    const text = this.steering.join('\n\n');
    this.steering = [];
    return text;
  }

  /**
   * Executes the calls of one step. Runs of consecutive read-only calls go in parallel; the rest
   * run in order. Always returns one result per call, in call order.
   */
  private async runTools(calls: MessagePart[], cancel: CancelToken, state: BatchState): Promise<MessagePart[]> {
    const results: MessagePart[] = [];
    let i = 0;
    while (i < calls.length) {
      let j = i;
      while (j < calls.length && this.isParallel(calls[j])) {
        j++;
      }
      if (j - i > 1) {
        const group = calls.slice(i, j);
        for (const c of group) {
          this.announce(c);
        }
        const parts = await Promise.all(group.map((c: MessagePart) => this.execute(c, cancel, state)));
        for (const p of parts) {
          results.push(p);
        }
        i = j;
        continue;
      }
      this.announce(calls[i]);
      results.push(await this.execute(calls[i], cancel, state));
      i++;
    }
    return results;
  }

  private isParallel(call: MessagePart): boolean {
    const tool = this.deps.tools.get(call.toolName);
    return tool !== undefined && tool.kind === ToolKind.READ;
  }

  private announce(call: MessagePart): void {
    const tool = this.deps.tools.get(call.toolName);
    const label: ToolLabel = tool !== undefined ? this.safeLabel(tool, call.argumentsJson) :
      { verbKey: 'agent_tool_unknown', target: call.toolName };
    this.listener.onToolCall({
      callId: call.callId, toolName: call.toolName, kind: tool !== undefined ? tool.kind : '',
      label: label, argumentsJson: call.argumentsJson
    });
  }

  private async execute(call: MessagePart, cancel: CancelToken, state: BatchState): Promise<MessagePart> {
    const tool = this.deps.tools.get(call.toolName);
    if (cancel.cancelled) {
      return this.finish(call, ToolOutput.error(CANCELLED_RESULT), ToolCallStatus.CANCELLED);
    }
    if (state.halted) {
      return this.finish(call, ToolOutput.error(SKIPPED_RESULT), ToolCallStatus.CANCELLED);
    }
    if (tool === undefined) {
      return this.finish(call, ToolOutput.error(`Unknown tool "${call.toolName}". Available tools: ` +
        this.deps.tools.names().join(', ') + '.'), ToolCallStatus.FAILED);
    }
    const ctx: ToolContext = {
      paths: this.deps.paths, fs: this.deps.fs, shell: this.deps.shell, cancel: cancel, reads: this.reads,
      host: this, callId: call.callId, prompter: this.deps.prompter, jobs: this.deps.jobs, web: this.deps.web,
      subagents: this.deps.allowSubagents ? this : null
    };
    let args: ToolArgs;
    try {
      args = ToolArgs.parse(call.argumentsJson);
    } catch (e) {
      return this.finish(call, ToolOutput.error((e as Error).message), ToolCallStatus.FAILED);
    }
    const ruleKey = tool.kind === ToolKind.EXECUTE ? ApprovalPolicy.commandKey(args.optStr('command', '')) : '';
    if (this.deps.policy.needsApproval(tool.kind, ruleKey)) {
      let preview = '';
      try {
        preview = await tool.preview(args, ctx);
      } catch (e) {
        // The call is invalid (e.g. the edit text isn't in the file): report it without asking.
        return this.finish(call, ToolOutput.error((e as Error).message), ToolCallStatus.FAILED);
      }
      this.listener.onToolStatus(call.callId, ToolCallStatus.AWAITING_APPROVAL);
      const reply = await this.ask({
        callId: call.callId, toolName: call.toolName, kind: tool.kind, label: this.safeLabel(tool, call.argumentsJson),
        preview: preview, ruleKey: ruleKey
      }, cancel);
      if (reply.decision === ApprovalDecision.DENY) {
        const fb = reply.feedback.trim();
        const text = 'The user denied this action.' + (fb.length > 0 ? ' Their instructions: ' + fb :
          ' Stop and wait for the user\'s next message.');
        if (fb.length === 0) {
          state.halted = true;
        }
        return this.finish(call, ToolOutput.error(text), ToolCallStatus.DENIED);
      }
      if (reply.decision === ApprovalDecision.APPROVE_ALWAYS) {
        this.deps.policy.allowAlways(tool.kind, ruleKey);
      }
    }
    this.listener.onToolStatus(call.callId, ToolCallStatus.RUNNING);
    let result: ToolOutput;
    try {
      result = await tool.run(args, ctx);
    } catch (e) {
      if (CancelToken.isCancellation(e as Error) || cancel.cancelled) {
        return this.finish(call, ToolOutput.error('Cancelled by the user while running.'), ToolCallStatus.CANCELLED);
      }
      const msg = e instanceof ToolInputError ? (e as Error).message : 'Tool failed: ' + (e as Error).message;
      result = ToolOutput.error(msg);
    }
    this.warnOnRepeat(call, result);
    if (result.changedFiles.length > 0) {
      this.listener.onFilesChanged(result.changedFiles);
    }
    return this.finish(call, result, result.isError ? ToolCallStatus.FAILED : ToolCallStatus.DONE);
  }

  private ask(req: ApprovalRequest, cancel: CancelToken): Promise<ApprovalReply> {
    // A pending approval ends as a denial when the turn is stopped.
    return new Promise<ApprovalReply>((resolve: (r: ApprovalReply) => void, reject: (e: Error) => void) => {
      let done = false;
      const off = cancel.onCancel(() => {
        if (!done) {
          done = true;
          resolve({ decision: ApprovalDecision.DENY, feedback: '' });
        }
      });
      this.deps.gate.request(req)
        .then((r: ApprovalReply) => {
          if (!done) {
            done = true;
            off();
            resolve(r);
          }
        })
        .catch((e: Error) => {
          if (!done) {
            done = true;
            off();
            reject(e);
          }
        });
    });
  }

  private finish(call: MessagePart, result: ToolOutput, status: string): MessagePart {
    const text = TextLimits.middle(result.text, AgentLimits.MAX_TOOL_OUTPUT_CHARS);
    this.listener.onToolOutput(call.callId, result);
    this.listener.onToolStatus(call.callId, status);
    return MessagePart.toolResult(call.callId, text, result.isError);
  }

  /** Models sometimes loop on an identical failing call; tell them to change course. */
  private warnOnRepeat(call: MessagePart, result: ToolOutput): void {
    // Polling a background job with the same arguments is expected.
    if (call.toolName === 'command_output') {
      return;
    }
    const key = call.toolName + '\n' + call.argumentsJson;
    this.repeatCount = key === this.lastCallKey ? this.repeatCount + 1 : 1;
    this.lastCallKey = key;
    if (this.repeatCount >= AgentLimits.REPEAT_WARN_COUNT) {
      result.text += `\n\n[Note: you have made this exact call ${this.repeatCount} times in a row. ` +
        'Try a different approach instead of repeating it.]';
    }
  }

  private safeLabel(tool: AgentTool, argumentsJson: string): ToolLabel {
    try {
      return tool.label(ToolArgs.parse(argumentsJson));
    } catch (e) {
      return tool.label(new ToolArgs({}));
    }
  }

  private reportUsage(input: number, output: number, system: string): void {
    if (input > 0) {
      this.lastContextTokens = input + output;
    } else {
      this.lastContextTokens = ContextManager.estimateTokens(system, this.history, this.deps.tools.specs());
    }
  }

  /** Prunes, then compacts, when the next request would not fit comfortably. */
  private async fitContext(system: string, cancel: CancelToken): Promise<void> {
    const window = this.deps.model.contextWindow;
    if (window <= 0) {
      return;
    }
    const limit = ContextManager.threshold(window);
    const specs = this.deps.tools.specs();
    let tokens = Math.max(this.lastContextTokens, ContextManager.estimateTokens(system, this.history, specs));
    if (tokens < limit) {
      return;
    }
    if (ContextManager.prune(this.history)) {
      tokens = ContextManager.estimateTokens(system, this.history, specs);
      this.lastContextTokens = tokens;
      if (tokens < limit) {
        return;
      }
    }
    this.history = await ContextManager.compact(this.deps.model, system, this.history, cancel);
    this.reads.clear();
    this.lastContextTokens = ContextManager.estimateTokens(system, this.history, specs);
    this.listener.onNotice(NoticeKind.COMPACTED, '');
  }
}
