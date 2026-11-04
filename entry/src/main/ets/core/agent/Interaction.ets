import { CancelToken } from '../llm/CancelToken';

/** One choice offered with a question. */
export interface QuestionOption {
  label: string;
  description: string;
}

/** A question the agent asks the user mid-task (ask_user). */
export interface UserQuestion {
  callId: string;
  question: string;
  options: QuestionOption[];
  multiSelect: boolean;
}

/** Shows questions to the user. The UI resolves with the answer text ('' when dismissed). */
export interface UserPrompter {
  ask(q: UserQuestion): Promise<string>;
}

/** Answers every question with "no answer" (sub-agents and tests without a UI). */
export class NoUserPrompter implements UserPrompter {
  ask(q: UserQuestion): Promise<string> {
    return Promise.resolve('');
  }
}

/** Progress reported by a sub-agent while it works. */
export type ProgressListener = (line: string) => void;

/** Runs a focused sub-agent with its own context (the task tool). */
export interface SubagentRunner {
  /** Resolves with the sub-agent's final report. */
  runSubagent(prompt: string, onProgress: ProgressListener, cancel: CancelToken): Promise<string>;
}
