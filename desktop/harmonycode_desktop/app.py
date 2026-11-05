"""Wires the desktop app together: config folder, identity, paired devices, workspace and server."""
from __future__ import annotations

import asyncio
import json
import platform
import queue
import threading
from pathlib import Path

from .crypto import Identity
from .server import LinkServer, default_config_dir
from .trust import Pairing, TrustStore, fingerprint, lan_addresses, pairing_uri
from .workspace import Workspace


class DesktopApp:
    """Runs the Link server on a background asyncio loop; the GUI (or the console) reads `events`."""

    def __init__(self, config_dir: Path | None, workspace: Path | None, port: int, name: str | None,
                 fixed_secret: bytes | None = None) -> None:
        self.config_dir = config_dir or default_config_dir()
        self.config_dir.mkdir(parents=True, exist_ok=True)
        self._settings_path = self.config_dir / "settings.json"
        self.settings = self._load_settings()
        if workspace is not None:
            self.settings["workspace"] = str(workspace)
        root = Path(self.settings.get("workspace") or (Path.home() / "HarmonyCode"))
        self.settings["workspace"] = str(root)
        self._save_settings()
        self.identity = Identity.load_or_create(self.config_dir / "identity.key")
        self.trust = TrustStore(self.config_dir / "devices.json")
        self.pairing = Pairing(fixed_secret)
        self.name = name or platform.node() or "Desktop"
        self.events: "queue.Queue[tuple[str, object]]" = queue.Queue()
        self.server = LinkServer(Workspace(root), self.identity, self.trust, self.pairing, self.name, port,
                                 lambda kind, detail: self.events.put((kind, detail)))
        self.loop = asyncio.new_event_loop()
        self._ready = threading.Event()
        self._error: BaseException | None = None

    # ---------- lifecycle ----------

    def start(self) -> None:
        threading.Thread(target=self._run, name="hclink", daemon=True).start()
        self._ready.wait()
        if self._error is not None:
            raise self._error

    def _run(self) -> None:
        asyncio.set_event_loop(self.loop)
        try:
            self.loop.run_until_complete(self.server.start())
        except BaseException as e:  # port in use, ...
            self._error = e
            self._ready.set()
            return
        self._ready.set()
        self.loop.run_forever()

    def call(self, fn) -> None:
        """Runs `fn` on the server's loop."""
        self.loop.call_soon_threadsafe(fn)

    # ---------- pairing ----------

    def pairing_uri(self) -> str:
        secret, _ = self.pairing.current()
        return pairing_uri(lan_addresses(), self.server.port, self.identity.public, secret, self.name)

    def pairing_expires(self) -> float:
        return self.pairing.current()[1]

    def new_pairing_code(self) -> None:
        self.pairing.renew()

    def fingerprint(self) -> str:
        return fingerprint(self.identity.public)

    # ---------- workspace ----------

    @property
    def workspace_root(self) -> Path:
        return self.server.workspace.root

    def set_workspace(self, root: Path) -> None:
        """Switches the shared folder (disconnects phones so they re-sync against it)."""
        self.settings["workspace"] = str(root)
        self._save_settings()

        def swap() -> None:
            ws = Workspace(root)
            ws.changes()
            self.server.workspace = ws
            for c in list(self.server.clients):
                c.writer.close()
        self.call(swap)

    def _load_settings(self) -> dict:
        try:
            return json.loads(self._settings_path.read_text("utf-8"))
        except (OSError, ValueError):
            return {}

    def _save_settings(self) -> None:
        self._settings_path.write_text(json.dumps(self.settings, indent=1), "utf-8")
