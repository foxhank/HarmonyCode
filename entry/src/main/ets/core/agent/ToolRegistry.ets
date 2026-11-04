import { ToolSpec } from '../llm/LlmTypes';
import { AgentTool } from './ToolTypes';
import { AskUserTool } from './tools/AskUserTool';
import { DeletePathTool } from './tools/DeletePathTool';
import { EditFileTool } from './tools/EditFileTool';
import { GlobTool } from './tools/GlobTool';
import { GrepTool } from './tools/GrepTool';
import { CommandOutputTool, KillCommandTool } from './tools/JobTools';
import { ListDirTool } from './tools/ListDirTool';
import { MovePathTool } from './tools/MovePathTool';
import { MultiEditTool } from './tools/MultiEditTool';
import { ReadFileTool } from './tools/ReadFileTool';
import { RunCommandTool } from './tools/RunCommandTool';
import { TaskTool } from './tools/TaskTool';
import { UpdatePlanTool } from './tools/UpdatePlanTool';
import { WebFetchTool, WebSearchTool } from './tools/WebTools';
import { WriteFileTool } from './tools/WriteFileTool';

/** Name -> tool. The agent offers exactly the registered tools to the model. */
export class ToolRegistry {
  private tools: Map<string, AgentTool> = new Map();

  register(tool: AgentTool): ToolRegistry {
    this.tools.set(tool.spec.name, tool);
    return this;
  }

  get(name: string): AgentTool | undefined {
    return this.tools.get(name);
  }

  specs(): ToolSpec[] {
    return Array.from(this.tools.values()).map((t: AgentTool) => t.spec);
  }

  names(): string[] {
    return Array.from(this.tools.keys());
  }

  /** The full agent: files, commands (foreground and background), web, plans, questions, sub-agents. */
  static coding(withWeb: boolean): ToolRegistry {
    const r = new ToolRegistry()
      .register(new ListDirTool())
      .register(new ReadFileTool())
      .register(new GlobTool())
      .register(new GrepTool())
      .register(new EditFileTool())
      .register(new MultiEditTool())
      .register(new WriteFileTool())
      .register(new MovePathTool())
      .register(new DeletePathTool())
      .register(new RunCommandTool())
      .register(new CommandOutputTool())
      .register(new KillCommandTool())
      .register(new UpdatePlanTool())
      .register(new AskUserTool())
      .register(new TaskTool());
    if (withWeb) {
      r.register(new WebSearchTool()).register(new WebFetchTool());
    }
    return r;
  }

  /** What a sub-agent gets: looking only, so it never needs the user's approval. */
  static explore(search: boolean, fetch: boolean): ToolRegistry {
    const r = new ToolRegistry()
      .register(new ListDirTool())
      .register(new ReadFileTool())
      .register(new GlobTool())
      .register(new GrepTool())
      .register(new CommandOutputTool());
    if (search) {
      r.register(new WebSearchTool());
    }
    if (fetch) {
      r.register(new WebFetchTool());
    }
    return r;
  }
}
