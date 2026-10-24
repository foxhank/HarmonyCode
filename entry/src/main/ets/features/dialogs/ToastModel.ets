import { AppConfig } from '../../core/common/AppConfig';

export enum ToastKind {
  INFO = 'info',
  ERROR = 'error'
}

/** Short, non-blocking messages. Rendered by ToastHost. */
@ObservedV2
export class ToastModel {
  @Trace message: string = '';
  @Trace kind: string = ToastKind.INFO;
  private timer: number = -1;

  info(message: string): void {
    this.show(message, ToastKind.INFO);
  }

  error(message: string): void {
    this.show(message, ToastKind.ERROR);
  }

  dismiss(): void {
    this.message = '';
  }

  private show(message: string, kind: string): void {
    this.message = message;
    this.kind = kind;
    if (this.timer >= 0) {
      clearTimeout(this.timer);
    }
    this.timer = setTimeout(() => {
      this.message = '';
      this.timer = -1;
    }, AppConfig.TOAST_DURATION);
  }
}

export const toasts: ToastModel = new ToastModel();
