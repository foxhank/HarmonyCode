import { PlanStep } from '../../core/agent/PlanTypes';
import { AppPaths } from '../../core/common/AppPaths';
import { Logger, errorMessage } from '../../core/common/Logger';
import { FileService } from '../../core/fs/FileService';
import { PathUtil } from '../../core/fs/PathUtil';
import { ChatMessage } from '../../core/llm/LlmTypes';
import { TranscriptItemJson } from './TranscriptItem';

const DIR: string = 'agent';
const TAG: string = 'AgentHistory';

/** One project's saved conversation. */
export interface SavedConversation {
  messages: ChatMessage[];
  items: TranscriptItemJson[];
  plan: PlanStep[];
}

/** Saves each project's agent conversation in the app's files folder (outside the project). */
export class AgentHistory {
  private file: string;

  constructor(projectId: string) {
    // AppPaths.workspace is <files>/workspace; conversations go to <files>/agent.
    const dir = PathUtil.join(PathUtil.dirName(AppPaths.workspace), DIR);
    this.file = PathUtil.join(dir, projectId.replace(new RegExp('[^A-Za-z0-9_-]', 'g'), '_') + '.json');
  }

  load(): SavedConversation | null {
    if (!FileService.exists(this.file)) {
      return null;
    }
    try {
      const saved = JSON.parse(FileService.readText(this.file)) as SavedConversation;
      saved.messages = (saved.messages ?? []).map((m: ChatMessage) => ChatMessage.fromJson(m));
      saved.items = saved.items ?? [];
      saved.plan = saved.plan ?? [];
      return saved;
    } catch (e) {
      Logger.warn(TAG, 'unreadable conversation: ' + errorMessage(e as Error));
      return null;
    }
  }

  save(c: SavedConversation): void {
    try {
      FileService.writeText(this.file, JSON.stringify(c));
    } catch (e) {
      Logger.warn(TAG, 'save failed: ' + errorMessage(e as Error));
    }
  }

  clear(): void {
    if (FileService.exists(this.file)) {
      FileService.remove(this.file);
    }
  }
}
