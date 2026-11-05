# HarmonyCode Desktop

The desktop companion of HarmonyCode. Scan its QR code with the phone app and a phone project stays
in sync with a folder on this computer in real time, both ways; Run, the terminal and the agent's
commands then run here. Windows and Linux (macOS later). Everything is encrypted end to end; see
[docs/desktop-link.md](../docs/desktop-link.md) for the design, protocol and security.

## Run

Python 3.10 or newer, with Tk (included in the Windows installer; on Debian/Ubuntu
`sudo apt install python3-tk`).

Windows:

```bash
python -m venv .venv
```

```bash
.venv\Scripts\pip install -r requirements.txt
```

```bash
.venv\Scripts\python -m harmonycode_desktop
```

Linux:

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```

```bash
.venv/bin/python -m harmonycode_desktop
```

Then in HarmonyCode on the phone: **Remote › HarmonyCode Desktop › Pair › Scan QR code**. Open a
project and choose the desktop under **Environment › Run on**.

Options: `--workspace DIR` (the shared folder, default `~/HarmonyCode`, also changeable in the
window), `--port N` (default 47110), `--name NAME`, `--headless` (no window; prints the pairing link).
The phone must reach the desktop on that port: same Wi-Fi/LAN, or a VPN such as Tailscale. Allow the
app through the firewall when Windows asks.

## Files

| Module | What it does |
|---|---|
| `server.py` | TCP server: handshake, encrypted records, file and command messages, change broadcasts |
| `workspace.py` | Safe path resolution, hash cache, compare-and-swap writes, polling watcher |
| `crypto.py` | Ed25519 identity, X25519, HMAC key derivation, AES-256-GCM records |
| `trust.py` | Paired phones, the one-time pairing secret, the pairing link |
| `protocol.py`, `wire.py`, `lz4.py` | Message codec, wire encoding, LZ4 block compression |
| `executor.py` | Runs commands (PowerShell on Windows, `/bin/sh` elsewhere), kills process trees |
| `gui.py` | The window: QR code, shared folder, live file tree and preview, devices, activity |

Settings, the identity key and paired devices live in `~/.harmonycode-desktop/`.

Tests (they start this app headless and run the phone's code against it):

```bash
node ../tests/link/build.mjs link
```
