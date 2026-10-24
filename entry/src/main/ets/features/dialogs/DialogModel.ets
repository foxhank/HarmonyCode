export enum ButtonRole {
  NORMAL = 'normal',
  PRIMARY = 'primary',
  DANGER = 'danger'
}

export interface DialogButton {
  label: ResourceStr;
  role: string;
}

export enum DialogKind {
  PROMPT = 'prompt',
  CONFIRM = 'confirm'
}

/** Returns an error message for invalid input, or '' when valid. */
export type Validator = (value: string) => string;

/** Result index used when a dialog is dismissed. */
export const DIALOG_CANCELLED: number = -1;

/**
 * Text-input and confirmation dialogs as promises, so models can ask the user
 * without knowing about UI. Rendered by DialogHost.
 */
@ObservedV2
export class DialogModel {
  @Trace visible: boolean = false;
  @Trace kind: string = DialogKind.CONFIRM;
  @Trace title: ResourceStr = '';
  @Trace message: ResourceStr = '';
  @Trace value: string = '';
  @Trace placeholder: ResourceStr = '';
  @Trace error: string = '';
  @Trace buttons: DialogButton[] = [];
  private validator: Validator | null = null;
  private resolveIndex: ((i: number) => void) | null = null;

  /** Asks for text. Resolves to the entered text, or null if cancelled. */
  prompt(title: ResourceStr, placeholder: ResourceStr, initial: string, ok: DialogButton, cancel: DialogButton,
    validator?: Validator): Promise<string | null> {
    this.open(DialogKind.PROMPT, title, '', [cancel, ok]);
    this.value = initial;
    this.placeholder = placeholder;
    this.validator = validator ?? null;
    return new Promise<string | null>((resolve: (v: string | null) => void) => {
      this.resolveIndex = (i: number) => resolve(i === 1 ? this.value.trim() : null);
    });
  }

  /** Asks to choose a button. Resolves to the button index, or DIALOG_CANCELLED. */
  confirm(title: ResourceStr, message: ResourceStr, buttons: DialogButton[]): Promise<number> {
    this.open(DialogKind.CONFIRM, title, message, buttons);
    return new Promise<number>((resolve: (i: number) => void) => {
      this.resolveIndex = resolve;
    });
  }

  setValue(v: string): void {
    this.value = v;
    if (this.error.length > 0) {
      this.error = '';
    }
  }

  /** Button pressed. For prompts, the OK button runs validation first. */
  press(index: number): void {
    if (this.kind === DialogKind.PROMPT && index === 1 && this.validator !== null) {
      const err = this.validator(this.value.trim());
      if (err.length > 0) {
        this.error = err;
        return;
      }
    }
    this.close(index);
  }

  cancel(): void {
    this.close(DIALOG_CANCELLED);
  }

  private open(kind: string, title: ResourceStr, message: ResourceStr, buttons: DialogButton[]): void {
    if (this.resolveIndex !== null) {
      this.close(DIALOG_CANCELLED); // a newer dialog replaces an open one
    }
    this.kind = kind;
    this.title = title;
    this.message = message;
    this.buttons = buttons;
    this.error = '';
    this.value = '';
    this.validator = null;
    this.visible = true;
  }

  private close(index: number): void {
    this.visible = false;
    const r = this.resolveIndex;
    this.resolveIndex = null;
    if (r !== null) {
      r(index);
    }
  }
}

export const dialogs: DialogModel = new DialogModel();
