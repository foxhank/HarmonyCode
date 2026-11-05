# HarmonyCode Link: phone ↔ desktop

HarmonyCode Link pairs the phone app with a small desktop companion (Windows and Linux now,
macOS later) by scanning a QR code. Once paired, a phone project and a folder on the desktop stay
in sync in real time, and the phone can run commands on the desktop (the agent, Run, a terminal).
This document is the contract both implementations follow:
`desktop/harmonycode_desktop` (Python) and `entry/src/main/ets/core/link` (ArkTS).

## 1. Architecture

```
 Phone (HarmonyCode)                                   Desktop (harmonycode-desktop)
 ┌───────────────────────────────┐                     ┌────────────────────────────────┐
 │ Workbench (editor, explorer,  │                     │ GUI: QR + LAN URL, paired      │
 │ agent, terminal)              │                     │ devices, live file tree,       │
 │   │ edits / FILES_CHANGED     │                     │ preview, activity log          │
 │ DesktopTarget                 │                     │   ▲ events                     │
 │   ├ LinkSync  (coordinator)   │  TCP, LAN, port     │ LinkServer (asyncio)           │
 │   ├ LinkRunner (commands)     │◄──────47110────────►│   ├ Session (handshake+AEAD)   │
 │   └ LinkClient                │  encrypted frames   │   ├ Workspace (files, watcher) │
 │       └ LinkSession           │                     │   ├ Executor (commands)        │
 │           (handshake + AEAD)  │                     │   └ TrustStore (paired phones) │
 └───────────────────────────────┘                     └────────────────────────────────┘
```

- **The phone coordinates sync.** It keeps the *base*: the content hash both sides agreed on last
  time, per file. With the phone's file, the desktop's file and the base, every case (edited
  here, edited there, deleted here or there, edited on both) is decided exactly. The desktop
  is a file server that also watches its folder and announces changes.
- **The desktop guards its files.** Writes and deletes are compare-and-swap on the content
  hash, so a desktop edit that races a phone upload is never silently overwritten.
- **Paths** in the protocol are POSIX, relative to the desktop's workspace root. A phone project
  maps to one top-level folder there (its name). The desktop refuses `..`, absolute paths, drive
  letters and anything that resolves outside the root (symlinks included).

## 2. Security

| Goal | How |
|---|---|
| Only someone who saw the QR code can pair | One-time 128-bit pairing secret in the QR code; the phone proves it with an HMAC over the handshake transcript. Valid for 10 minutes, single use, regenerated after each pairing. |
| No man-in-the-middle on first contact | The QR code also carries the desktop's Ed25519 identity key; the phone requires the server to sign the transcript with exactly that key. |
| Mutual authentication afterwards | Both sides keep long-term Ed25519 identities. Each connection, both sign the transcript; each side only accepts the peer key it stored at pairing. |
| Confidentiality, integrity, forward secrecy | Fresh X25519 key pair per connection on both sides; keys derived with HKDF-SHA256; every frame is AES-256-GCM with a per-direction counter nonce (no reuse, no replay, no reordering). |
| Revocation | The desktop lists paired phones and can remove one; the phone can forget a desktop. |
| Least surprise | The desktop only serves its chosen workspace folder, and only to paired phones. Commands run as the desktop user, in the workspace, because that is the feature. |

Identity keys: the desktop stores its key in `~/.harmonycode-desktop/identity.key` (owner-only
permissions); the phone stores its key in the system Asset Store.

## 3. Pairing URL (QR code content)

```
hclink://pair?v=1&a=192.168.1.20:47110,10.0.0.5:47110&k=<desktop Ed25519 public key, base64url>&s=<pairing secret, base64url>&n=<desktop name, URL-encoded>
```

`a` lists every LAN address of the desktop; the phone tries them in order. The same text is shown
as a link to copy, for phones without a camera.

## 4. Framing

All integers are big-endian. `str` = u32 length + UTF-8; `bytes` = u32 length + bytes.

- **Handshake frames** (plaintext): `u32 length || payload`, at most 4 KiB.
- **Records** (after keys): `u32 length || AES-256-GCM(key, nonce, aad = the 4 length bytes, plaintext)`,
  the length covering ciphertext and 16-byte tag. `nonce = 0x00000000 || u64 counter`; each
  direction has its own key and counter starting at 0. Plaintext at most 1 MiB. Any
  authentication failure closes the connection.

## 5. Handshake

```
H0 = SHA-256("HCLINK-v1")
C → S  CLIENT_HELLO  = "HCL1" || u8 version=1 || u8 mode (1 = pair, 2 = resume) || ce (32) || cr (16)
S → C  SERVER_HELLO  = "HCL1" || u8 version=1 || se (32) || sr (16) || spk (32, Ed25519) || sig (64)
         H1  = SHA-256(H0 || CLIENT_HELLO || SERVER_HELLO without sig)
         sig = Ed25519(server identity, H1)
         client checks spk == the expected key (QR code when pairing, stored key when resuming), and sig
keys:  ss  = X25519(ce_priv, se) = X25519(se_priv, ce)
       prk = HMAC-SHA256(key = H1, ss)
       k_c2s = HMAC-SHA256(prk, "c2s" || 0x01),  k_s2c = HMAC-SHA256(prk, "s2c" || 0x01)
C → S  CLIENT_AUTH (record) = cpk (32) || str name || sig_c (64) || bytes proof
         H2    = SHA-256(H1 || "client")
         sig_c = Ed25519(client identity, H2)
         proof = HMAC-SHA256(pairing secret, H2) when pairing, empty when resuming
         server checks sig_c; pairing: proof (constant time, unexpired, unused) then stores cpk + name;
         resuming: cpk must be a paired device
S → C  AUTH_OK  (record) = u8 0 || str desktop name || str workspace name || str os || str hostname
   or  AUTH_FAIL (record) = u8 1 || str reason, then close
```

## 6. Messages

Every record carries one message: `u8 type || u8 flags || u32 id || body`. Requests carry an
id > 0 that the reply repeats; id 0 means an unsolicited event. Flag bit 0: the body is
compressed, stored as `u32 raw length || LZ4 block` (sent only when it saves at least 1/16).

| Type | Name | Body | Reply |
|---|---|---|---|
| 0x01 | PING | u64 time | PONG (same body) |
| 0x02 | PONG | u64 time | |
| 0x10 | LIST | str prefix | ENTRIES |
| 0x11 | ENTRIES | u32 n, n × entry | |
| 0x12 | GET | str path, u64 offset | DATA (one or more until final) |
| 0x13 | DATA | str path, u64 total, u64 offset, u8 final, bytes32 hash, bytes chunk | |
| 0x14 | PUT | str path, bytes32 base, u64 total, u64 offset, u8 final, bytes chunk | RESULT after the final chunk |
| 0x15 | RESULT | u8 status, str message, bytes32 hash | |
| 0x16 | DELETE | str path, bytes32 base | RESULT |
| 0x17 | CHANGED | u32 n, n × entry (event, id 0) | |
| 0x20 | EXEC | str command, str cwd, u32 timeout ms | OUTPUT …, EXIT |
| 0x21 | OUTPUT | bytes chunk | |
| 0x22 | EXIT | i32 code, u8 timed out | |
| 0x23 | KILL | u32 exec id | |
| 0x7F | ERROR | str message | |

`entry = str path || u64 size || u64 mtime ms || bytes32 sha256 || u8 deleted`. An all-zero hash
means "no file" (as a PUT/DELETE base: the file must not exist). RESULT status: 0 ok, 1 conflict
(the desktop's file is not the base; `hash` is its current hash), 2 refused (bad path), 3 error.
Chunks are at most 512 KiB; files up to 256 MiB.

## 7. Sync

The phone keeps, per project and desktop: the base hash of every path, and a hash cache of its own
files (rehashed only when size or modification time changes).

```
for every path in phone ∪ desktop ∪ base:
  P = phone hash, D = desktop hash, B = base            (absent = none)
  P == D                → base := P
  D == B   (phone changed)    → P none ? DELETE(base B) : PUT(base B)      → base := P
  P == B   (desktop changed)  → D none ? delete phone file : GET           → base := D
  otherwise (both changed)    → GET desktop copy to "<path>.conflict", PUT phone version (base D)
```

- **When:** after connecting (full LIST), on every CHANGED event, whenever a file is saved or
  changed on the phone (debounced 300 ms), before and after each command, and every 30 s as a
  safety net.
- **Races:** a PUT/DELETE whose base no longer matches gets RESULT conflict; the phone refreshes
  that path and decides again.
- **Echo suppression:** the desktop remembers the hashes it just wrote for a client and does not
  announce those back to it; other clients do get the CHANGED event.
- **Not synced:** `.git`, `node_modules`, `.venv`, `venv`, `__pycache__`, `build`, `dist`, `target`,
  `.gradle`, `.idea`, `.next`, `.cache`, `oh_modules`, `.hvigor` (dependencies and build output stay
  where they were made).

## 8. Commands

EXEC runs `command` with the desktop's shell (`/bin/sh -c` on Linux and macOS, PowerShell on
Windows) in `cwd` (relative to the workspace root), streaming stdout and stderr as OUTPUT and ending
with EXIT. KILL (or the connection closing) ends the process tree. The phone syncs before and after,
so commands see the phone's latest files and the phone sees what the commands produced.
