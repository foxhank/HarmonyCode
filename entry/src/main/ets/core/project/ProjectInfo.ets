/** A project in the recent-projects list. Plain data, persisted as JSON. */
export interface ProjectInfo {
  id: string;
  name: string;
  path: string;
  envId: string;
  templateId: string;
  runCommand: string;
  createdAt: number;
  lastOpened: number;
}

export function copyProject(p: ProjectInfo): ProjectInfo {
  return {
    id: p.id, name: p.name, path: p.path, envId: p.envId, templateId: p.templateId,
    runCommand: p.runCommand, createdAt: p.createdAt, lastOpened: p.lastOpened
  };
}
