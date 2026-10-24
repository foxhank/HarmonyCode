import { ButtonRole, DialogButton } from './DialogModel';

/** Common dialog buttons. */
export class Buttons {
  static ok(): DialogButton {
    return { label: $r('app.string.action_ok'), role: ButtonRole.PRIMARY };
  }

  static cancel(): DialogButton {
    return { label: $r('app.string.action_cancel'), role: ButtonRole.NORMAL };
  }

  static create(): DialogButton {
    return { label: $r('app.string.action_create'), role: ButtonRole.PRIMARY };
  }

  static rename(): DialogButton {
    return { label: $r('app.string.action_rename'), role: ButtonRole.PRIMARY };
  }

  static del(): DialogButton {
    return { label: $r('app.string.action_delete'), role: ButtonRole.DANGER };
  }

  static save(): DialogButton {
    return { label: $r('app.string.action_save'), role: ButtonRole.PRIMARY };
  }

  static dontSave(): DialogButton {
    return { label: $r('app.string.action_dont_save'), role: ButtonRole.NORMAL };
  }

  static discard(): DialogButton {
    return { label: $r('app.string.action_discard'), role: ButtonRole.DANGER };
  }

  static of(label: ResourceStr, role: string): DialogButton {
    return { label: label, role: role };
  }
}
