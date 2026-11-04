import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import { errorMessage } from '../common/Logger';

/** A running download. `done` rejects on failure or cancel. */
export interface DownloadHandle {
  done: Promise<void>;
  cancel: () => void;
}

/** Message of the error `done` rejects with after cancel(). */
export const DOWNLOAD_CANCELLED: string = 'download cancelled';

/** Downloads `url` to `dest` (an app sandbox path) with the system download agent. */
export function downloadFile(ctx: common.Context, url: string, dest: string,
  onProgress: (done: number, total: number) => void): DownloadHandle {
  let task: request.agent.Task | null = null;
  let cancelled = false;
  let rejectDone: ((e: Error) => void) | null = null;
  const config: request.agent.Config = {
    action: request.agent.Action.DOWNLOAD,
    url: url,
    saveas: dest,
    overwrite: true,
    mode: request.agent.Mode.FOREGROUND,
    network: request.agent.Network.ANY,
    retry: true,
    gauge: false
  };
  const done = new Promise<void>((resolve: () => void, reject: (e: Error) => void) => {
    rejectDone = reject;
    request.agent.create(ctx, config).then((t: request.agent.Task) => {
      task = t;
      if (cancelled) {
        request.agent.remove(t.tid).catch(() => {
        });
        reject(new Error(DOWNLOAD_CANCELLED));
        return;
      }
      t.on('progress', (p: request.agent.Progress) => {
        const total = p.sizes.length > 0 ? p.sizes[0] : -1;
        onProgress(p.processed, total);
      });
      t.on('completed', () => resolve());
      t.on('failed', () => {
        if (cancelled) {
          reject(new Error(DOWNLOAD_CANCELLED));
          return;
        }
        request.agent.show(t.tid).then((info: request.agent.TaskInfo) => {
          reject(new Error(info.reason.length > 0 ? info.reason : 'download failed'));
        }).catch((e: Error) => reject(e));
      });
      return t.start();
    }).catch((e: Error) => reject(new Error(errorMessage(e))));
  });
  return {
    done: done,
    cancel: () => {
      cancelled = true;
      if (rejectDone !== null) {
        rejectDone(new Error(DOWNLOAD_CANCELLED));
      }
      const t = task;
      if (t !== null) {
        request.agent.remove(t.tid).catch(() => {
        });
      }
    }
  };
}
