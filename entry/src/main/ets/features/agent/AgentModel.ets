import { AgentListener, NoticeKind, ToolCallStatus, ToolCallView, TurnStatus } from '../../core/agent/AgentEvents';
import { AgentFs } from '../../core/agent/AgentFs';
import { ApprovalDecision, ApprovalGate, ApprovalPolicy, ApprovalReply, ApprovalRequest } from '../../core/agent/Approval';
import { AgentSession } from '../../core/agent/AgentSession';
import { BackgroundJobs } from '../../core/agent/BackgroundJobs';
import { CommandRunner } from '../../core/agent/CommandRunner';
import { UserPrompter, UserQuestion } from '../../core/agent/Interaction';
import { PathGuard } from '../../core/agent/PathGuard';
import { PlanStep, StepStatus } from '../../core/agent/PlanTypes';
import { ToolRegistry } from '../../core/agent/ToolRegistry';
import { ToolOutput } from '../../core/agent/ToolTypes';
import { Strings } from '../../core/common/Strings';
import { ChatModel } from '../../core/llm/ChatModel';
import { ChatMessage, TokenUsage } from '../../core/llm/LlmTypes';
import { modelLabel } from '../../core/llm/ProviderConfig';
import { AgentSettingsStore } from '../../core/settings/AgentSettingsStore';
import { BackgroundKeeper } from '../app/BackgroundKeeper';
import { AgentHistory } from './AgentHistory';
import { LlmServices } from './LlmServices';
import { ItemKind, TranscriptItem, TranscriptItemJson } from './TranscriptItem';

/** Streaming text is applied to the UI at most this often. */
const FLUSH_MS: number = 60;

/** What the agent panel needs from where it works: an open project, or a remote computer. */
export interface AgentHost {
  /** Key under which the conversation is saved. */
  projectId(): string;
  projectName(): string;
  /** WorkspaceKind.PROJECT or WorkspaceKind.REMOTE. */
  workspaceKind(): string;
  /** Working folder and how far the agent may reach. */
  paths(): PathGuard;
  fs(): AgentFs;
  shell(): CommandRunner;
  /** Files changed by the agent ('' = unknown: refresh everything). */
  filesChanged(paths: string[]): void;
  openFile(path: string): void;
  openAgentSettings(): void;
  today(): string;
}

/** A pending ask_user question and how to answer it. */
class PendingQuestion {
  item: TranscriptItem;
  resolve: (answer: string) => void;

  constructor(item: TranscriptItem, resolve: (answer: string) => void) {
    this.item = item;
    this.resolve = resolve;
  }
}

/** A pending approval and how to answer it. */
class PendingApproval {
  item: TranscriptItem;
  resolve: (r: ApprovalReply) => void;

  constructor(item: TranscriptItem, resolve: (r: ApprovalReply) => void) {
    this.item = item;
    this.resolve = resolve;
  }
}

/**
 * State behind the agent panel: the transcript, the plan, the composer and approvals. Turns
 * AgentSession events into observable items and persists the conversation per project.
 */
@ObservedV2
export class AgentModel implements AgentListener, ApprovalGate, UserPrompter {
  @Trace items: TranscriptItem[] = [];
  @Trace plan: PlanStep[] = [];
  @Trace draft: string = '';
  @Trace busy: boolean = false;
  @Trace contextUsed: number = 0;
  @Trace contextWindow: number = 0;
  /** Bumped whenever the transcript grows, so the view can scroll to the end. */
  @Trace revision: number = 0;
  readonly settings: AgentSettingsStore;
  private host: AgentHost;
  private history: AgentHistory;
  private session: AgentSession | null = null;
  private nextId: number = 1;
  private textItem: TranscriptItem | null = null;
  private reasoningItem: TranscriptItem | null = null;
  private pendingText: string = '';
  private pendingReasoning: string = '';
  private flushTimer: number = -1;
  private approvals: Map<string, PendingApproval> = new Map();
  private questions: Map<string, PendingQuestion> = new Map();
  private jobs: BackgroundJobs = new BackgroundJobs();
  /** Conversation loaded from disk, handed to the session when it is created. */
  private restoredMessages: ChatMessage[] = [];

  constructor(host: AgentHost, settings: AgentSettingsStore) {
    this.host = host;
    this.settings = settings;
    this.history = new AgentHistory(host.projectId());
    this.restore();
  }

  // ---------- commands from the view ----------

  get hasModel(): boolean {
    return this.settings.resolve() !== null;
  }

  modelName(): string {
    const r = this.settings.resolve();
    return r === null ? '' : modelLabel(r.model);
  }

  send(): void {
    const text = this.draft.trim();
    if (text.length === 0) {
      return;
    }
    if (this.busy) {
      // Mid-turn: the agent reads it with its next tool results.
      if (this.session !== null && this.session.steer(text)) {
        this.draft = '';
        const queued = this.add(ItemKind.USER);
        queued.text = text;
        queued.queued = true;
      }
      return;
    }
    const resolved = this.settings.resolve();
    if (resolved === null) {
      this.host.openAgentSettings();
      return;
    }
    // Remote endpoints need a key; local servers (plain http, e.g. Ollama) usually don't.
    if (resolved.provider.apiKey.length === 0 && !resolved.provider.baseUrl.trim().startsWith('http://')) {
      this.addError(Strings.get('agent_error_no_key', resolved.provider.name));
      return;
    }
    this.draft = '';
    const model = LlmServices.model(resolved.provider, resolved.model);
    const session = this.ensureSession(model);
    session.configure(model, this.settings.maxSteps, this.settings.requestTemperature(), this.settings.approvalMode,
      this.settings.customInstructions);
    session.setWeb(this.settings.webEnabled ? LlmServices.web : null);
    const user = this.add(ItemKind.USER);
    user.text = text;
    this.busy = true;
    session.send(text);
  }

  stop(): void {
    this.session?.stop();
  }

  /** Clears the conversation. */
  newChat(): void {
    if (this.busy) {
      return;
    }
    this.session?.reset();
    this.items = [];
    this.plan = [];
    this.contextUsed = 0;
    this.history.clear();
    this.revision++;
  }

  /** Answers an ask_user question ('' = dismissed). */
  reply(item: TranscriptItem, answer: string): void {
    const q = this.questions.get(item.callId);
    if (q === undefined) {
      return;
    }
    this.questions.delete(item.callId);
    item.question = '';
    item.options = [];
    q.resolve(answer);
  }

  answer(item: TranscriptItem, decision: string, feedback: string): void {
    const p = this.approvals.get(item.callId);
    if (p === undefined) {
      return;
    }
    this.approvals.delete(item.callId);
    item.preview = '';
    p.resolve({ decision: decision, feedback: feedback });
  }

  openFile(target: string): void {
    if (target.length === 0) {
      return;
    }
    try {
      this.host.openFile(this.host.paths().resolve(target));
    } catch (e) {
      // a path outside the project: nothing to open
    }
  }

  openSettings(): void {
    this.host.openAgentSettings();
  }

  selectModel(providerId: string, modelId: string): void {
    this.settings.select(providerId, modelId);
  }

  dispose(): void {
    BackgroundKeeper.release(this.keeperKey());
    this.session?.dispose();
    this.jobs.killAll();
    for (const p of this.approvals.values()) {
      p.resolve({ decision: ApprovalDecision.DENY, feedback: '' });
    }
    this.approvals.clear();
    for (const q of this.questions.values()) {
      q.resolve('');
    }
    this.questions.clear();
  }

  // ---------- UserPrompter ----------

  ask(q: UserQuestion): Promise<string> {
    return new Promise<string>((resolve: (answer: string) => void) => {
      const item = this.toolItem(q.callId);
      if (item === undefined) {
        resolve('');
        return;
      }
      item.question = q.question;
      item.options = q.options;
      item.multiSelect = q.multiSelect;
      item.expanded = true;
      this.questions.set(q.callId, new PendingQuestion(item, resolve));
      this.revision++;
    });
  }

  // ---------- ApprovalGate ----------

  request(req: ApprovalRequest): Promise<ApprovalReply> {
    return new Promise<ApprovalReply>((resolve: (r: ApprovalReply) => void) => {
      const item = this.toolItem(req.callId);
      if (item === undefined) {
        resolve({ decision: ApprovalDecision.DENY, feedback: '' });
        return;
      }
      item.preview = req.preview;
      item.ruleKey = req.ruleKey;
      item.expanded = true;
      this.approvals.set(req.callId, new PendingApproval(item, resolve));
      this.revision++;
    });
  }

  // ---------- AgentListener ----------

  onTurnStart(): void {
    this.busy = true;
    BackgroundKeeper.acquire(this.keeperKey());
  }

  onStepStart(step: number): void {
    this.endStreaming();
  }

  onTextDelta(text: string): void {
    this.pendingText += text;
    this.scheduleFlush();
  }

  onReasoningDelta(text: string): void {
    this.pendingReasoning += text;
    this.scheduleFlush();
  }

  onToolCall(call: ToolCallView): void {
    this.endStreaming();
    const t = this.add(ItemKind.TOOL);
    t.callId = call.callId;
    t.toolName = call.toolName;
    t.toolKind = call.kind;
    t.verbKey = call.label.verbKey;
    t.target = call.label.target;
    t.status = ToolCallStatus.RUNNING;
  }

  onToolStatus(callId: string, status: string): void {
    const t = this.toolItem(callId);
    if (t !== undefined) {
      t.status = status;
      if (status !== ToolCallStatus.AWAITING_APPROVAL && status !== ToolCallStatus.RUNNING) {
        t.live = '';
      }
    }
  }

  onToolOutput(callId: string, output: ToolOutput): void {
    const t = this.toolItem(callId);
    if (t !== undefined) {
      t.output = output.text;
      t.display = output.display;
      t.isError = output.isError;
    }
  }

  onCommandOutput(callId: string, chunk: string): void {
    const t = this.toolItem(callId);
    if (t !== undefined) {
      t.live = (t.live + chunk).slice(-8000);
    }
  }

  onPlan(steps: PlanStep[], explanation: string): void {
    this.plan = steps.map((s: PlanStep): PlanStep => {
      return { step: s.step, status: StepStatus.normalize(s.status) };
    });
  }

  onUsage(usage: TokenUsage, contextTokens: number, contextWindow: number): void {
    this.contextUsed = contextTokens;
    this.contextWindow = contextWindow;
  }

  onNotice(kind: string, detail: string): void {
    this.endStreaming();
    const n = this.add(ItemKind.NOTICE);
    n.text = kind === NoticeKind.COMPACTED ? 'agent_notice_compacted' :
      (kind === NoticeKind.TRUNCATED ? 'agent_notice_truncated' : 'agent_notice_retrying');
  }

  onFilesChanged(paths: string[]): void {
    this.host.filesChanged(paths);
  }

  onTurnEnd(status: string, error: string): void {
    this.endStreaming();
    // A stopped turn leaves no question open.
    for (const q of this.questions.values()) {
      q.item.question = '';
      q.resolve('');
    }
    this.questions.clear();
    for (const i of this.items) {
      i.queued = false;
    }
    if (status === TurnStatus.ERROR) {
      this.addError(error);
    } else if (status === TurnStatus.CANCELLED) {
      this.add(ItemKind.NOTICE).text = 'agent_notice_stopped';
    } else if (status === TurnStatus.STEP_LIMIT) {
      this.add(ItemKind.NOTICE).text = 'agent_notice_step_limit';
    }
    this.busy = false;
    BackgroundKeeper.release(this.keeperKey());
    this.persist();
  }

  private keeperKey(): string {
    return 'agent:' + this.host.projectId();
  }

  // ---------- internals ----------

  private ensureSession(model: ChatModel): AgentSession {
    if (this.session !== null) {
      return this.session;
    }
    const shell = this.host.shell();
    const paths = this.host.paths();
    const web = this.settings.webEnabled ? LlmServices.web : null;
    const s = new AgentSession({
      model: model,
      fs: this.host.fs(),
      shell: shell,
      paths: paths,
      tools: ToolRegistry.coding(web !== null),
      policy: new ApprovalPolicy(this.settings.approvalMode),
      gate: this,
      prompter: this,
      jobs: this.jobs,
      web: web,
      env: {
        kind: this.host.workspaceKind(), projectName: this.host.projectName(), root: paths.root, shell: shell.describe(),
        today: this.host.today(), customInstructions: this.settings.customInstructions, web: web !== null,
        subagent: false
      },
      maxSteps: this.settings.maxSteps,
      temperature: this.settings.requestTemperature(),
      allowSubagents: true
    }, this);
    if (this.restoredMessages.length > 0) {
      s.restore(this.restoredMessages);
    }
    this.session = s;
    return s;
  }

  private restore(): void {
    const saved = this.history.load();
    if (saved === null) {
      return;
    }
    this.restoredMessages = saved.messages;
    this.items = saved.items.map((j: TranscriptItemJson) => TranscriptItem.fromJson(j));
    this.plan = saved.plan;
    for (const i of this.items) {
      this.nextId = Math.max(this.nextId, i.id + 1);
    }
  }

  private persist(): void {
    const messages = this.session !== null ? this.session.messages() : this.restoredMessages;
    this.history.save({
      messages: messages,
      items: this.items.filter((i: TranscriptItem) => i.kind !== ItemKind.REASONING)
        .map((i: TranscriptItem) => i.toJson()),
      plan: this.plan
    });
  }

  private add(kind: string): TranscriptItem {
    const item = new TranscriptItem(this.nextId++, kind);
    this.items.push(item);
    this.revision++;
    return item;
  }

  private addError(message: string): void {
    this.add(ItemKind.ERROR).text = message;
  }

  private toolItem(callId: string): TranscriptItem | undefined {
    for (let i = this.items.length - 1; i >= 0; i--) {
      if (this.items[i].kind === ItemKind.TOOL && this.items[i].callId === callId) {
        return this.items[i];
      }
    }
    return undefined;
  }

  private scheduleFlush(): void {
    if (this.flushTimer >= 0) {
      return;
    }
    this.flushTimer = setTimeout(() => {
      this.flushTimer = -1;
      this.flush();
    }, FLUSH_MS);
  }

  private flush(): void {
    if (this.pendingReasoning.length > 0) {
      if (this.reasoningItem === null) {
        this.reasoningItem = this.add(ItemKind.REASONING);
        this.reasoningItem.streaming = true;
      }
      this.reasoningItem.text += this.pendingReasoning;
      this.pendingReasoning = '';
    }
    if (this.pendingText.length > 0) {
      if (this.textItem === null) {
        this.textItem = this.add(ItemKind.ASSISTANT);
        this.textItem.streaming = true;
      }
      this.textItem.text += this.pendingText;
      this.pendingText = '';
      this.revision++;
    }
  }

  /** Writes out buffered text and closes the current text/reasoning items. */
  private endStreaming(): void {
    if (this.flushTimer >= 0) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
    this.flush();
    if (this.textItem !== null) {
      this.textItem.streaming = false;
    }
    if (this.reasoningItem !== null) {
      this.reasoningItem.streaming = false;
    }
    this.textItem = null;
    this.reasoningItem = null;
  }
}
