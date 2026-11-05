# Remote (SSH) tests

These tests run the app's own `core/remote` sources under Node, against an independent SSH server:
the [`ssh2`](https://www.npmjs.com/package/ssh2) package (a test-only dependency, see `package.json`).
Node's `crypto` and `net` stand in for the HarmonyOS crypto framework and sockets (`NodeSsh.ts`).

Install the test dependency once, then run a suite with the Node that ships with DevEco Studio:

```bash
npm install --no-audit --no-fund --ignore-scripts
```

```bash
node build.mjs ssh
```

```bash
node build.mjs remote
```

```bash
node build.mjs sync
```

```bash
node build.mjs agent path/to/account.txt anthropic
```

- `ssh`: the SSH client itself. Every key exchange (curve25519, DH group 14), cipher (AES-GCM,
  AES-CTR) and MAC (HMAC-SHA2, ETM) it offers; ed25519, ECDSA and RSA host keys; password,
  keyboard-interactive and public-key login; exit codes, stderr, flow control with large output,
  UTF-8, parallel channels, stdin/EOF; a terminal with resize; server-initiated re-keying; SFTP;
  a jump host; keepalives; and error messages for refused keys and non-SSH ports.
- `remote`: the remote workspace layer. Platform probe, the agent's file system over SFTP, commands
  in a working folder with timeout and stop (the process is killed on the server), background jobs,
  reconnecting after the link drops, jump hosts with key login, and the agent's tools on the remote
  machine.
- `sync`: two-way project sync between a phone folder and a computer folder (first upload, edits
  and deletions in both directions, conflicts, dependency folders left alone, binary files) and
  running a phone project's commands on the computer with the results synced back.
- `agent`: live, end to end. A real model works on the "remote computer" only through SSH: it fixes
  failing tests, runs a server in the background and stops it, and asks the user a question. The
  account file is the same as for `tests/agent`.

The test server runs commands with the local `bash` (Git Bash on Windows).
