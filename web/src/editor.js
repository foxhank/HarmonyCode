// HarmonyCode editor view. The ArkTS side owns tabs and files; this page only
// renders documents. Calls in:  window.hc.*   Calls out: window.hcNative.*
import { EditorState, Compartment } from '@codemirror/state';
import { EditorView, keymap } from '@codemirror/view';
import { basicSetup } from 'codemirror';
import { indentWithTab } from '@codemirror/commands';
import { indentUnit, StreamLanguage } from '@codemirror/language';
import { oneDark } from '@codemirror/theme-one-dark';
import { unifiedMergeView } from '@codemirror/merge';
import { javascript } from '@codemirror/lang-javascript';
import { python } from '@codemirror/lang-python';
import { cpp } from '@codemirror/lang-cpp';
import { java } from '@codemirror/lang-java';
import { rust } from '@codemirror/lang-rust';
import { go } from '@codemirror/lang-go';
import { json } from '@codemirror/lang-json';
import { markdown } from '@codemirror/lang-markdown';
import { html } from '@codemirror/lang-html';
import { css } from '@codemirror/lang-css';
import { xml } from '@codemirror/lang-xml';
import { yaml } from '@codemirror/lang-yaml';
import { sql } from '@codemirror/lang-sql';
import { shell } from '@codemirror/legacy-modes/mode/shell';
import { toml } from '@codemirror/legacy-modes/mode/toml';

const native = () => window.hcNative;

function languageFor(name) {
  const lower = name.toLowerCase();
  const ext = lower.includes('.') ? lower.slice(lower.lastIndexOf('.') + 1) : lower;
  switch (ext) {
    case 'js': case 'mjs': case 'cjs': return javascript();
    case 'jsx': return javascript({ jsx: true });
    case 'ts': case 'mts': case 'ets': return javascript({ typescript: true });
    case 'tsx': return javascript({ typescript: true, jsx: true });
    case 'json': case 'json5': return json();
    case 'py': case 'pyw': return python();
    case 'c': case 'h': case 'cc': case 'cpp': case 'cxx': case 'hpp': return cpp();
    case 'java': case 'kt': return java();
    case 'rs': return rust();
    case 'go': return go();
    case 'md': case 'markdown': return markdown();
    case 'html': case 'htm': case 'vue': return html();
    case 'css': case 'scss': case 'less': return css();
    case 'xml': case 'svg': return xml();
    case 'yml': case 'yaml': return yaml();
    case 'sql': return sql();
    case 'sh': case 'bash': case 'zsh': case 'makefile': case 'dockerfile': return StreamLanguage.define(shell);
    case 'toml': return StreamLanguage.define(toml);
    default: return [];
  }
}

export function languageLabel(name) {
  const l = name.toLowerCase();
  const ext = l.includes('.') ? l.slice(l.lastIndexOf('.') + 1) : '';
  const map = { js: 'JavaScript', ts: 'TypeScript', ets: 'ArkTS', py: 'Python', c: 'C', cpp: 'C++', h: 'C/C++ Header',
    java: 'Java', rs: 'Rust', go: 'Go', md: 'Markdown', json: 'JSON', html: 'HTML', css: 'CSS', yml: 'YAML',
    yaml: 'YAML', sh: 'Shell', toml: 'TOML', sql: 'SQL', xml: 'XML' };
  return map[ext] || 'Plain Text';
}

// Settings shared by every document.
const options = { fontSize: 14, tabSize: 4, wrap: false, dark: true, background: '' };
const themeConf = new Compartment();
const colorConf = new Compartment();
const wrapConf = new Compartment();
const tabConf = new Compartment();

function themeExt() {
  return EditorView.theme({
    '&': { fontSize: options.fontSize + 'px' },
    '.cm-content': { paddingBottom: '40vh' },
  });
}

// Light or dark syntax colors; the background always matches the app's editor color.
function colorExt() {
  const bg = options.background ? { '&': { backgroundColor: options.background }, '.cm-gutters': { backgroundColor: options.background } } : {};
  return [options.dark ? oneDark : [], EditorView.theme(bg, { dark: options.dark })];
}

// Debounced change notifications so ArkTS always has a recent copy of each document
// (needed to restore tabs if the view is rebuilt, e.g. on rotation or resize).
const pending = new Map();
function scheduleChanged(id, state) {
  clearTimeout(pending.get(id));
  pending.set(id, setTimeout(() => {
    pending.delete(id);
    native()?.changed(id, state.doc.toString());
  }, 250));
}
function flush(id) {
  if (!pending.has(id)) return;
  clearTimeout(pending.get(id));
  pending.delete(id);
  const st = id === currentId ? view.state : docs.get(id)?.state;
  if (st) native()?.changed(id, st.doc.toString());
}

const commandKeys = keymap.of([
  { key: 'Mod-s', preventDefault: true, run: () => { saveDoc(currentId); return true; } },
  { key: 'Mod-Alt-s', preventDefault: true, run: () => { hc.requestSaveAll(); return true; } },
  { key: 'Mod-p', preventDefault: true, run: () => cmd('quickOpen') },
  { key: 'Mod-Shift-p', preventDefault: true, run: () => cmd('palette') },
  { key: 'F1', preventDefault: true, run: () => cmd('palette') },
  { key: 'Mod-`', preventDefault: true, run: () => cmd('toggleTerminal') },
  { key: 'Mod-j', preventDefault: true, run: () => cmd('toggleTerminal') },
  { key: 'Mod-b', preventDefault: true, run: () => cmd('toggleSidebar') },
  { key: 'Mod-w', preventDefault: true, run: () => cmd('closeTab') },
  { key: 'Mod-Shift-f', preventDefault: true, run: () => cmd('search') },
  { key: 'Mod-Shift-g', preventDefault: true, run: () => cmd('git') },
  { key: 'Mod-Shift-e', preventDefault: true, run: () => cmd('explorer') },
  { key: 'Ctrl-Tab', preventDefault: true, run: () => cmd('nextTab') },
  { key: 'Ctrl-Shift-Tab', preventDefault: true, run: () => cmd('prevTab') },
  { key: 'F5', preventDefault: true, run: () => cmd('run') },
]);
function cmd(name) { native()?.command(name); return true; }

function makeState(id, text, name, readOnly) {
  return EditorState.create({
    doc: text,
    extensions: [
      commandKeys,
      basicSetup,
      keymap.of([indentWithTab]),
      colorConf.of(colorExt()),
      themeConf.of(themeExt()),
      wrapConf.of(options.wrap ? EditorView.lineWrapping : []),
      tabConf.of([EditorState.tabSize.of(options.tabSize), indentUnit.of(' '.repeat(options.tabSize))]),
      languageFor(name),
      EditorState.readOnly.of(!!readOnly),
      EditorView.updateListener.of((u) => {
        if (u.docChanged) scheduleChanged(id, u.state);
        if (u.selectionSet || u.docChanged) {
          const head = u.state.selection.main.head;
          const line = u.state.doc.lineAt(head);
          native()?.cursor(line.number, head - line.from + 1);
        }
      }),
    ],
  });
}

const docs = new Map(); // id -> { state, name }
let currentId = '';
const view = new EditorView({ parent: document.getElementById('editor') });
let diffView = null;

function saveDoc(id) {
  if (!id) return;
  const st = id === currentId ? view.state : docs.get(id)?.state;
  if (!st) return;
  clearTimeout(pending.get(id));
  pending.delete(id);
  native()?.save(id, st.doc.toString());
}

function showEditor() {
  document.getElementById('editor').style.display = 'block';
  document.getElementById('diff').style.display = 'none';
}

const hc = {
  /** Open (or replace, with force) a document and show it. */
  open(id, text, name, readOnly, force) {
    const existing = docs.get(id);
    if (!existing || force) {
      if (existing && id === currentId) existing.state = view.state;
      docs.set(id, { state: makeState(id, text, name, readOnly), name });
    }
    hc.show(id);
  },
  show(id) {
    if (currentId && docs.has(currentId)) docs.get(currentId).state = view.state;
    const d = docs.get(id);
    if (!d) return;
    currentId = id;
    showEditor();
    view.setState(d.state);
    const head = d.state.selection.main.head;
    const line = d.state.doc.lineAt(head);
    native()?.cursor(line.number, head - line.from + 1);
  },
  close(id) {
    flush(id);
    docs.delete(id);
    if (currentId === id) currentId = '';
  },
  rename(oldId, newId, name) {
    const d = docs.get(oldId);
    if (!d) return;
    const st = oldId === currentId ? view.state : d.state;
    docs.delete(oldId);
    docs.set(newId, { state: makeState(newId, st.doc.toString(), name, false), name });
    if (currentId === oldId) { currentId = ''; hc.show(newId); }
  },
  requestSave(id) { saveDoc(id || currentId); },
  requestSaveAll() { for (const id of docs.keys()) saveDoc(id); },
  focus() { view.focus(); },
  gotoLine(line, col) {
    const doc = view.state.doc;
    const l = doc.line(Math.max(1, Math.min(line, doc.lines)));
    const pos = Math.min(l.to, l.from + Math.max(0, (col || 1) - 1));
    view.dispatch({ selection: { anchor: pos }, scrollIntoView: true });
    view.focus();
  },
  setOptions(fontSize, tabSize, wrap) {
    options.fontSize = fontSize; options.tabSize = tabSize; options.wrap = wrap;
    const effects = [
      themeConf.reconfigure(themeExt()),
      wrapConf.reconfigure(wrap ? EditorView.lineWrapping : []),
      tabConf.reconfigure([EditorState.tabSize.of(tabSize), indentUnit.of(' '.repeat(tabSize))]),
    ];
    view.dispatch({ effects });
    for (const [id, d] of docs) {
      if (id !== currentId) d.state = d.state.update({ effects }).state;
    }
  },
  /** dark: boolean; background: CSS color of the editor surface. */
  setTheme(dark, background) {
    options.dark = !!dark;
    options.background = background || '';
    document.body.style.background = options.background;
    const effects = colorConf.reconfigure(colorExt());
    view.dispatch({ effects });
    if (diffView) diffView.dispatch({ effects });
    for (const [id, d] of docs) {
      if (id !== currentId) d.state = d.state.update({ effects }).state;
    }
  },
  /** Read-only unified diff of `original` (e.g. HEAD) against `modified` (working tree). */
  openDiff(id, original, modified, name) {
    if (currentId && docs.has(currentId)) docs.get(currentId).state = view.state;
    currentId = id;
    const host = document.getElementById('diff');
    host.innerHTML = '';
    if (diffView) diffView.destroy();
    diffView = new EditorView({
      parent: host,
      state: EditorState.create({
        doc: modified,
        extensions: [
          commandKeys, basicSetup, colorConf.of(colorExt()), themeConf.of(themeExt()),
          languageFor(name), EditorState.readOnly.of(true), EditorView.editable.of(false),
          unifiedMergeView({ original, mergeControls: false, highlightChanges: true, gutter: true }),
        ],
      }),
    });
    document.getElementById('editor').style.display = 'none';
    host.style.display = 'block';
  },
  languageLabel,
};
window.hc = hc;

window.addEventListener('blur', () => { for (const id of [...pending.keys()]) flush(id); });
native()?.ready();
