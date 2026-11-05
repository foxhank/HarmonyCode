"""The desktop window: QR code to pair, the shared folder live, paired phones and activity."""
from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path


def _find_tcl() -> None:
    """Virtual environments of some Windows Python builds can't find Tcl/Tk; point them at the base install."""
    if sys.platform != "win32" or "TCL_LIBRARY" in os.environ:
        return
    base = Path(sys.base_prefix) / "tcl"
    for name, var in (("tcl8.6", "TCL_LIBRARY"), ("tk8.6", "TK_LIBRARY")):
        if (base / name).is_dir():
            os.environ[var] = str(base / name)


_find_tcl()

import tkinter as tk  # noqa: E402 (after locating Tcl)
from tkinter import filedialog, messagebox, ttk  # noqa: E402

import qrcode  # noqa: E402

from .app import DesktopApp  # noqa: E402
from .protocol import IGNORED_DIRS  # noqa: E402

POLL_MS = 150
TREE_REFRESH_MS = 400
HIGHLIGHT_S = 6
PREVIEW_MAX = 200_000
BG = "#F1F3F5"
CARD = "#FFFFFF"
ACCENT = "#0A59F7"
MUTED = "#5C5C66"
FONT = ("Segoe UI", 10) if sys.platform == "win32" else ("Sans", 10)
MONO = ("Consolas", 10) if sys.platform == "win32" else ("Monospace", 10)


class Window:
    def __init__(self, app: DesktopApp) -> None:
        self.app = app
        self.root = tk.Tk()
        self.root.title("HarmonyCode Desktop")
        self.root.geometry("1080x680")
        self.root.minsize(860, 560)
        self.root.configure(bg=BG)
        self._recent: dict[str, float] = {}
        self._tree_dirty = True
        self._preview_path = ""
        self._qr_uri = ""
        self._style()
        self._build()
        self._refresh_pairing()
        self._refresh_devices()
        self.root.after(POLL_MS, self._poll)
        self.root.after(TREE_REFRESH_MS, self._tree_tick)
        self.root.after(1000, self._clock)

    # ---------- layout ----------

    def _style(self) -> None:
        s = ttk.Style(self.root)
        if "vista" in s.theme_names():
            s.theme_use("vista")
        elif "clam" in s.theme_names():
            s.theme_use("clam")
        s.configure("Card.TFrame", background=CARD)
        s.configure("Bg.TFrame", background=BG)
        s.configure("Title.TLabel", background=CARD, font=(FONT[0], 15, "bold"))
        s.configure("Card.TLabel", background=CARD, font=FONT)
        s.configure("Muted.TLabel", background=CARD, foreground=MUTED, font=(FONT[0], 9))
        s.configure("Treeview", rowheight=24, font=FONT)

    def _build(self) -> None:
        outer = ttk.Frame(self.root, style="Bg.TFrame", padding=14)
        outer.pack(fill="both", expand=True)
        left = ttk.Frame(outer, style="Card.TFrame", padding=16)
        left.pack(side="left", fill="y")
        right = ttk.Frame(outer, style="Bg.TFrame")
        right.pack(side="left", fill="both", expand=True, padx=(14, 0))

        ttk.Label(left, text="Pair your phone", style="Title.TLabel").pack(anchor="w")
        ttk.Label(left, text="In HarmonyCode: Remote › Pair desktop, then scan.", style="Muted.TLabel").pack(anchor="w", pady=(2, 10))
        self.qr = tk.Canvas(left, width=264, height=264, bg=CARD, highlightthickness=0)
        self.qr.pack()
        self.expiry = ttk.Label(left, text="", style="Muted.TLabel")
        self.expiry.pack(anchor="w", pady=(6, 0))
        row = ttk.Frame(left, style="Card.TFrame")
        row.pack(fill="x", pady=(8, 0))
        self.uri = tk.StringVar()
        ttk.Entry(row, textvariable=self.uri, state="readonly", width=30).pack(side="left", fill="x", expand=True)
        ttk.Button(row, text="Copy", command=self._copy_uri).pack(side="left", padx=(6, 0))
        ttk.Button(left, text="New code", command=self._new_code).pack(anchor="w", pady=(8, 0))
        ttk.Label(left, text=f"Desktop key {self.app.fingerprint()}", style="Muted.TLabel").pack(anchor="w", pady=(10, 0))
        ttk.Label(left, text=f"Port {self.app.server.port}", style="Muted.TLabel").pack(anchor="w")

        ttk.Separator(left).pack(fill="x", pady=14)
        ttk.Label(left, text="Shared folder", style="Card.TLabel").pack(anchor="w")
        self.folder = ttk.Label(left, text=str(self.app.workspace_root), style="Muted.TLabel", wraplength=264)
        self.folder.pack(anchor="w", pady=(2, 6))
        row2 = ttk.Frame(left, style="Card.TFrame")
        row2.pack(anchor="w")
        ttk.Button(row2, text="Change…", command=self._change_folder).pack(side="left")
        ttk.Button(row2, text="Open", command=self._open_folder).pack(side="left", padx=(6, 0))

        nb = ttk.Notebook(right)
        nb.pack(fill="both", expand=True)
        files = ttk.Frame(nb, padding=8)
        nb.add(files, text="Files")
        pane = ttk.PanedWindow(files, orient="horizontal")
        pane.pack(fill="both", expand=True)
        tree_box = ttk.Frame(pane)
        self.tree = ttk.Treeview(tree_box, columns=("size", "changed"), show="tree headings")
        self.tree.heading("#0", text="Name")
        self.tree.heading("size", text="Size")
        self.tree.heading("changed", text="Changed")
        self.tree.column("#0", width=260)
        self.tree.column("size", width=80, anchor="e")
        self.tree.column("changed", width=120)
        self.tree.tag_configure("recent", foreground=ACCENT, font=(FONT[0], FONT[1], "bold"))
        sb = ttk.Scrollbar(tree_box, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=sb.set)
        self.tree.pack(side="left", fill="both", expand=True)
        sb.pack(side="left", fill="y")
        self.tree.bind("<<TreeviewSelect>>", lambda _e: self._select())
        pane.add(tree_box, weight=1)
        prev_box = ttk.Frame(pane)
        self.preview_title = ttk.Label(prev_box, text="Select a file to preview it; it updates as it changes.")
        self.preview_title.pack(anchor="w")
        self.preview = tk.Text(prev_box, wrap="none", font=MONO, state="disabled", bg="#FAFBFC", relief="flat")
        self.preview.pack(fill="both", expand=True, pady=(4, 0))
        pane.add(prev_box, weight=1)

        devices = ttk.Frame(nb, padding=8)
        nb.add(devices, text="Devices")
        self.devices = ttk.Treeview(devices, columns=("state", "seen"), show="tree headings", height=8)
        self.devices.heading("#0", text="Phone")
        self.devices.heading("state", text="Status")
        self.devices.heading("seen", text="Last seen")
        self.devices.pack(fill="both", expand=True)
        ttk.Button(devices, text="Remove pairing", command=self._remove_device).pack(anchor="w", pady=(8, 0))

        log = ttk.Frame(nb, padding=8)
        nb.add(log, text="Activity")
        self.log = tk.Listbox(log, font=FONT, relief="flat", activestyle="none")
        self.log.pack(fill="both", expand=True)

    # ---------- pairing ----------

    def _refresh_pairing(self) -> None:
        uri = self.app.pairing_uri()
        self.uri.set(uri)
        if uri != self._qr_uri:
            self._qr_uri = uri
            self._draw_qr(uri)

    def _draw_qr(self, text: str) -> None:
        qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, border=2)
        qr.add_data(text)
        qr.make(fit=True)
        matrix = qr.get_matrix()
        size = int(self.qr["width"])
        cell = max(1, size // len(matrix))
        pad = (size - cell * len(matrix)) // 2
        self.qr.delete("all")
        for y, line in enumerate(matrix):
            for x, dark in enumerate(line):
                if dark:
                    x0, y0 = pad + x * cell, pad + y * cell
                    self.qr.create_rectangle(x0, y0, x0 + cell, y0 + cell, fill="#000000", outline="")

    def _copy_uri(self) -> None:
        self.root.clipboard_clear()
        self.root.clipboard_append(self.uri.get())
        self._log("Pairing link copied")

    def _new_code(self) -> None:
        self.app.new_pairing_code()
        self._refresh_pairing()

    def _clock(self) -> None:
        left = int(self.app.pairing_expires() - time.time())
        if left <= 0:
            self._refresh_pairing()
            left = int(self.app.pairing_expires() - time.time())
        self.expiry.configure(text=f"Code valid for {left // 60}:{left % 60:02d} · used once")
        self.root.after(1000, self._clock)

    # ---------- folder ----------

    def _change_folder(self) -> None:
        d = filedialog.askdirectory(initialdir=str(self.app.workspace_root), title="Folder shared with the phone")
        if d:
            self.app.set_workspace(Path(d))
            self.folder.configure(text=d)
            self._tree_dirty = True
            self._log(f"Shared folder: {d}")

    def _open_folder(self) -> None:
        p = str(self.app.workspace_root)
        if sys.platform == "win32":
            os.startfile(p)  # noqa: S606 - opens the user's own folder
        else:
            subprocess.Popen(["xdg-open", p])

    # ---------- files ----------

    def _tree_tick(self) -> None:
        if self._tree_dirty:
            self._tree_dirty = False
            self._rebuild_tree()
        elif any(time.time() - t > HIGHLIGHT_S for t in self._recent.values()):
            self._recent = {k: t for k, t in self._recent.items() if time.time() - t <= HIGHLIGHT_S}
            self._rebuild_tree()
        self.root.after(TREE_REFRESH_MS, self._tree_tick)

    def _rebuild_tree(self) -> None:
        open_ids = {i for i in self._all_items() if self.tree.item(i, "open")}
        selected = self.tree.selection()
        self.tree.delete(*self.tree.get_children())
        root = self.app.workspace_root
        nodes: dict[str, str] = {"": ""}
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = sorted(d for d in dirnames if d not in IGNORED_DIRS)
            rel_dir = Path(dirpath).relative_to(root).as_posix()
            rel_dir = "" if rel_dir == "." else rel_dir
            for d in dirnames:
                rel = f"{rel_dir}/{d}" if rel_dir else d
                nodes[rel] = self.tree.insert(nodes[rel_dir], "end", iid="d:" + rel, text="📁 " + d,
                                              open=("d:" + rel) in open_ids)
            for f in sorted(filenames):
                if f.endswith(".hclink-tmp"):
                    continue
                rel = f"{rel_dir}/{f}" if rel_dir else f
                try:
                    st = os.stat(os.path.join(dirpath, f))
                except OSError:
                    continue
                recent = rel in self._recent
                self.tree.insert(nodes[rel_dir], "end", iid="f:" + rel, text=f,
                                 values=(_size(st.st_size), time.strftime("%H:%M:%S", time.localtime(st.st_mtime))),
                                 tags=("recent",) if recent else ())
                if recent:
                    parent = rel_dir
                    while parent:
                        self.tree.item("d:" + parent, open=True)
                        parent = parent.rpartition("/")[0]
        for s in selected:
            if self.tree.exists(s):
                self.tree.selection_set(s)

    def _all_items(self, parent: str = ""):
        for i in self.tree.get_children(parent):
            yield i
            yield from self._all_items(i)

    def _select(self) -> None:
        sel = self.tree.selection()
        if sel and sel[0].startswith("f:"):
            self._preview_path = sel[0][2:]
            self._show_preview()

    def _show_preview(self) -> None:
        rel = self._preview_path
        path = self.app.workspace_root / rel
        try:
            data = path.read_bytes()[:PREVIEW_MAX]
            text = "(binary file)" if b"\x00" in data[:8000] else data.decode("utf-8", errors="replace")
        except OSError:
            text = "(deleted)"
        self.preview_title.configure(text=rel)
        self.preview.configure(state="normal")
        self.preview.delete("1.0", "end")
        self.preview.insert("1.0", text)
        self.preview.configure(state="disabled")

    # ---------- devices ----------

    def _refresh_devices(self) -> None:
        online = set(self.app.server.connected_names())
        self.devices.delete(*self.devices.get_children())
        for d in self.app.trust.devices():
            seen = time.strftime("%Y-%m-%d %H:%M", time.localtime(d.last_seen)) if d.last_seen else "never"
            self.devices.insert("", "end", iid=d.key, text=d.name,
                                values=("● connected" if d.name in online else "paired", seen))

    def _remove_device(self) -> None:
        sel = self.devices.selection()
        if not sel:
            return
        name = self.devices.item(sel[0], "text")
        if messagebox.askyesno("Remove pairing", f"{name} will need to scan the QR code again. Remove it?"):
            self.app.trust.remove(sel[0])
            key = sel[0]
            self.app.call(lambda: self.app.server.disconnect(key))
            self._refresh_devices()
            self._log(f"Removed {name}")

    # ---------- events ----------

    def _log(self, text: str) -> None:
        self.log.insert(0, time.strftime("%H:%M:%S  ") + text)
        if self.log.size() > 500:
            self.log.delete(500, "end")

    def _poll(self) -> None:
        while True:
            try:
                kind, detail = self.app.events.get_nowait()
            except Exception:
                break
            if kind == "log":
                self._log(str(detail))
            elif kind in ("devices", "clients"):
                self._refresh_devices()
            elif kind == "pairing":
                self._refresh_pairing()
            elif kind == "files":
                now = time.time()
                for p in detail:  # type: ignore[union-attr]
                    self._recent[p] = now
                    if p == self._preview_path:
                        self._show_preview()
                self._tree_dirty = True
        self.root.after(POLL_MS, self._poll)

    def run(self) -> int:
        self.root.mainloop()
        return 0


def _size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return str(n)


def run_gui(app: DesktopApp) -> int:
    return Window(app).run()
