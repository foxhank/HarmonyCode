// HarmonyCode terminal view. The shell itself (hiSH VM or the built-in shell)
// runs on the ArkTS side; this page only renders and forwards keystrokes.
import '@xterm/xterm/css/xterm.css';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';

const native = () => window.hcTermNative;

// ANSI palettes tuned for dark and light backgrounds. Surface colors (background,
// foreground, cursor, selection) come from the app via hcTerm.setTheme().
const ANSI_DARK = {
  black: '#000000', red: '#cd3131', green: '#0dbc79', yellow: '#e5e510', blue: '#2472c8',
  magenta: '#bc3fbc', cyan: '#11a8cd', white: '#e5e5e5', brightBlack: '#666666', brightRed: '#f14c4c',
  brightGreen: '#23d18b', brightYellow: '#f5f543', brightBlue: '#3b8eea', brightMagenta: '#d670d6',
  brightCyan: '#29b8db', brightWhite: '#e5e5e5',
};
const ANSI_LIGHT = {
  black: '#000000', red: '#cd3131', green: '#107c10', yellow: '#949800', blue: '#0451a5',
  magenta: '#bc05bc', cyan: '#0598bc', white: '#555555', brightBlack: '#666666', brightRed: '#cd3131',
  brightGreen: '#14ce14', brightYellow: '#b5ba00', brightBlue: '#0451a5', brightMagenta: '#bc05bc',
  brightCyan: '#0598bc', brightWhite: '#a5a5a5',
};

const term = new Terminal({
  cursorBlink: true,
  fontSize: 13,
  fontFamily: '"HarmonyOS Sans Mono", "JetBrains Mono", Menlo, Consolas, monospace',
  scrollback: 5000,
  theme: ANSI_DARK,
});
const fit = new FitAddon();
term.loadAddon(fit);
term.open(document.getElementById('term'));

// Ctrl state from the on-screen extra-keys bar (phones/tablets without keyboards).
let stickyCtrl = false;
term.onData((data) => {
  if (stickyCtrl && data.length === 1) {
    const c = data.toUpperCase().charCodeAt(0);
    if (c >= 64 && c <= 95) data = String.fromCharCode(c - 64);
    stickyCtrl = false;
    native()?.ctrlConsumed();
  }
  native()?.input(data);
});

function doFit() {
  try { fit.fit(); } catch (e) { /* not visible yet */ }
  native()?.resize(term.cols, term.rows);
}
new ResizeObserver(() => doFit()).observe(document.getElementById('term'));

window.hcTerm = {
  write(s) { term.write(s); },
  reset() { term.reset(); },
  clear() { term.clear(); },
  focus() { term.focus(); },
  setFontSize(n) { term.options.fontSize = n; doFit(); },
  /** dark: boolean; colors: { background, foreground, cursor, selection } as CSS colors. */
  setTheme(dark, background, foreground, cursor, selection) {
    term.options.theme = Object.assign({}, dark ? ANSI_DARK : ANSI_LIGHT,
      { background, foreground, cursor, cursorAccent: background, selectionBackground: selection });
    document.body.style.background = background;
  },
  setCtrl(on) { stickyCtrl = !!on; term.focus(); },
  send(seq) { native()?.input(seq); term.focus(); },
  paste(text) { term.paste(text); },
  /** Re-announces readiness (called by the app on page load in case the bridge arrived late). */
  boot() { doFit(); native()?.ready(term.cols, term.rows); },
};

doFit();
native()?.ready(term.cols, term.rows);
