"""harmonycode-desktop: pair your phone and keep a workspace in sync.

    python -m harmonycode_desktop                  window with QR code, devices and live files
    python -m harmonycode_desktop --headless       console only (servers, tests)
"""
import argparse
import sys
import time
from pathlib import Path

from .app import DesktopApp
from .protocol import DEFAULT_PORT


def main() -> int:
    ap = argparse.ArgumentParser(prog="harmonycode-desktop", description="HarmonyCode desktop companion")
    ap.add_argument("--workspace", type=Path, help="folder shared with the phone (default: remembered, else ~/HarmonyCode)")
    ap.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"TCP port (default {DEFAULT_PORT}; 0 = any free port)")
    ap.add_argument("--name", help="name shown on the phone (default: this computer's name)")
    ap.add_argument("--config", type=Path, help="settings folder (default: ~/.harmonycode-desktop)")
    ap.add_argument("--headless", action="store_true", help="no window: print the pairing link and log to the console")
    ap.add_argument("--pair-secret", help=argparse.SUPPRESS)  # tests only: a fixed pairing secret (hex)
    args = ap.parse_args()
    secret = bytes.fromhex(args.pair_secret) if args.pair_secret else None
    app = DesktopApp(args.config, args.workspace, args.port, args.name, secret)
    try:
        app.start()
    except OSError as e:
        print(f"Cannot listen on port {args.port}: {e}", file=sys.stderr)
        return 1
    if args.headless:
        return run_console(app)
    from .gui import run_gui
    return run_gui(app)


def run_console(app: DesktopApp) -> int:
    print(f"HCLINK_READY {app.server.port}", flush=True)
    print(f"HCLINK_WORKSPACE {app.workspace_root}", flush=True)
    print(f"HCLINK_FINGERPRINT {app.fingerprint()}", flush=True)
    print(f"HCLINK_PAIR {app.pairing_uri()}", flush=True)
    try:
        while True:
            try:
                kind, detail = app.events.get(timeout=0.5)
            except Exception:
                continue
            if kind == "log":
                print(f"[{time.strftime('%H:%M:%S')}] {detail}", flush=True)
            elif kind == "pairing":
                print(f"HCLINK_PAIR {app.pairing_uri()}", flush=True)
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
