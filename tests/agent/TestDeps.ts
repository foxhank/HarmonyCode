// Builds AgentSession dependencies and tool contexts for the Node tests.
import { AgentDeps } from '../../entry/src/main/ets/core/agent/AgentSession';
import { ApprovalDecision, ApprovalGate, ApprovalPolicy } from '../../entry/src/main/ets/core/agent/Approval';
import { BackgroundJobs } from '../../entry/src/main/ets/core/agent/BackgroundJobs';
import { CommandRunner } from '../../entry/src/main/ets/core/agent/CommandRunner';
import { NoUserPrompter, UserPrompter } from '../../entry/src/main/ets/core/agent/Interaction';
import { PathGuard } from '../../entry/src/main/ets/core/agent/PathGuard';
import { ReadTracker } from '../../entry/src/main/ets/core/agent/ReadTracker';
import { WorkspaceKind } from '../../entry/src/main/ets/core/agent/SystemPrompt';
import { ToolRegistry } from '../../entry/src/main/ets/core/agent/ToolRegistry';
import { ToolContext } from '../../entry/src/main/ets/core/agent/ToolTypes';
import { WebAccess } from '../../entry/src/main/ets/core/agent/web/WebAccess';
import { CancelToken } from '../../entry/src/main/ets/core/llm/CancelToken';
import { ChatModel } from '../../entry/src/main/ets/core/llm/ChatModel';
import { NodeAgentFs, NodeCommandRunner } from './NodeAgentFs';

export const approveAll: ApprovalGate = { request: async () => ({ decision: ApprovalDecision.APPROVE, feedback: '' }) };

export interface DepOptions {
  mode: string;
  gate?: ApprovalGate;
  prompter?: UserPrompter;
  web?: WebAccess | null;
  shell?: CommandRunner;
  maxSteps?: number;
  name?: string;
}

export function makeDeps(model: ChatModel, root: string, o: DepOptions): AgentDeps {
  const shell = o.shell ?? new NodeCommandRunner();
  const web = o.web ?? null;
  return {
    model: model, fs: new NodeAgentFs(), shell: shell, paths: new PathGuard(root, true),
    tools: ToolRegistry.coding(web !== null), policy: new ApprovalPolicy(o.mode), gate: o.gate ?? approveAll,
    prompter: o.prompter ?? new NoUserPrompter(), jobs: new BackgroundJobs(), web: web,
    env: {
      kind: WorkspaceKind.PROJECT, projectName: o.name ?? 'p', root: root, shell: shell.describe(), today: '2026-11-04',
      customInstructions: '', web: web !== null, subagent: false
    },
    maxSteps: o.maxSteps ?? 30, temperature: NaN, allowSubagents: true
  };
}

export function makeCtx(root: string, confined: boolean = true): ToolContext {
  return {
    paths: new PathGuard(root, confined), fs: new NodeAgentFs(), shell: new NodeCommandRunner(), cancel: new CancelToken(),
    reads: new ReadTracker(), host: { planUpdated: () => {}, commandOutput: () => {} }, callId: 'c',
    prompter: new NoUserPrompter(), jobs: new BackgroundJobs(), web: null, subagents: null
  };
}
