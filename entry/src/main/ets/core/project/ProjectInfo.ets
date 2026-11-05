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
  /** Run on this saved computer instead of the device ('' or missing = on the device). */
  remoteHostId?: string;
  /** Folder on that computer (or in the desktop's workspace) the project is mirrored to ('' = default). */
  remoteDir?: string;
  /** Run on this paired HarmonyCode Desktop ('' or missing = not). */
  desktopId?: string;
}

export function runsOnDesktop(p: ProjectInfo): boolean {
  return p.desktopId !== undefined && p.desktopId.length > 0;
}

export function runsRemotely(p: ProjectInfo): boolean {
  return p.remoteHostId !== undefined && p.remoteHostId.length > 0;
}

export function copyProject(p: ProjectInfo): ProjectInfo {
  return {
    id: p.id, name: p.name, path: p.path, envId: p.envId, templateId: p.templateId,
    runCommand: p.runCommand, createdAt: p.createdAt, lastOpened: p.lastOpened,
    remoteHostId: p.remoteHostId ?? '', remoteDir: p.remoteDir ?? '', desktopId: p.desktopId ?? ''
  };
}
