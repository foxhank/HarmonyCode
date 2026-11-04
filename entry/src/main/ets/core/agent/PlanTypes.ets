/** Status of a plan step. */
export class StepStatus {
  static readonly PENDING: string = 'pending';
  static readonly IN_PROGRESS: string = 'in_progress';
  static readonly COMPLETED: string = 'completed';

  static normalize(s: string): string {
    if (s === StepStatus.IN_PROGRESS || s === StepStatus.COMPLETED) {
      return s;
    }
    return StepStatus.PENDING;
  }
}

/** One step of the agent's task plan. */
export interface PlanStep {
  step: string;
  status: string;
}
