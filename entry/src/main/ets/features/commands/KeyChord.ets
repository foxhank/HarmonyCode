import { KeyCode } from '@kit.InputKit';

const CTRL: string = 'Ctrl';
const SHIFT: string = 'Shift';
const ALT: string = 'Alt';
const JOIN: string = '+';

/** Named keys that commands use in their shortcut strings (see WorkbenchCommands). */
const NAMED: Map<number, string> = new Map<number, string>([
  [KeyCode.KEYCODE_TAB, 'Tab'],
  [KeyCode.KEYCODE_GRAVE, '`'],
  [KeyCode.KEYCODE_COMMA, ','],
  [KeyCode.KEYCODE_ENTER, 'Enter'],
  [KeyCode.KEYCODE_ESCAPE, 'Esc'],
]);

function keyName(code: number): string {
  if (code >= KeyCode.KEYCODE_A && code <= KeyCode.KEYCODE_Z) {
    return String.fromCharCode('A'.charCodeAt(0) + code - KeyCode.KEYCODE_A);
  }
  if (code >= KeyCode.KEYCODE_0 && code <= KeyCode.KEYCODE_9) {
    return (code - KeyCode.KEYCODE_0).toString();
  }
  if (code >= KeyCode.KEYCODE_F1 && code <= KeyCode.KEYCODE_F12) {
    return 'F' + (code - KeyCode.KEYCODE_F1 + 1).toString();
  }
  return NAMED.get(code) ?? '';
}

function hasModifier(e: KeyEvent, mod: string): boolean {
  return e.getModifierKeyState !== undefined && e.getModifierKeyState([mod]);
}

function isModifier(code: number): boolean {
  return code === KeyCode.KEYCODE_CTRL_LEFT || code === KeyCode.KEYCODE_CTRL_RIGHT ||
    code === KeyCode.KEYCODE_SHIFT_LEFT || code === KeyCode.KEYCODE_SHIFT_RIGHT ||
    code === KeyCode.KEYCODE_ALT_LEFT || code === KeyCode.KEYCODE_ALT_RIGHT;
}

/**
 * Turns a key-down event into the same text form commands declare, e.g. 'Ctrl+Shift+P'.
 * Returns '' for key-up, bare modifiers and keys no command can use.
 */
export function chordOf(e: KeyEvent): string {
  if (e.type !== KeyType.Down || isModifier(e.keyCode)) {
    return '';
  }
  const key = keyName(e.keyCode);
  if (key.length === 0) {
    return '';
  }
  const parts: string[] = [];
  for (const mod of [CTRL, ALT, SHIFT]) {
    if (hasModifier(e, mod)) {
      parts.push(mod);
    }
  }
  parts.push(key);
  return parts.join(JOIN);
}
