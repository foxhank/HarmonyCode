"""The HarmonyCode Link server: handshake, encrypted records, and the file and command messages."""
from __future__ import annotations

import asyncio
import platform
import socket
import struct
from pathlib import Path
from typing import Callable

from . import executor, protocol as P
from .crypto import Direction, Ephemeral, Identity, ed25519_verify, hmac_sha256, random_bytes, sha256
from .trust import Pairing, TrustStore
from .wire import Reader, WireError, Writer
from .workspace import PathRefused, Workspace

WATCH_INTERVAL_S = 0.7
HANDSHAKE_TIMEOUT_S = 15

# GUI events: (kind, detail). Kinds: "log", "devices", "clients", "files".
EventSink = Callable[[str, object], None]


class AuthError(Exception):
    pass


class Client:
    """One connected, authenticated phone."""

    def __init__(self, server: "LinkServer", reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        self.server = server
        self.reader = reader
        self.writer = writer
        self.send_dir: Direction | None = None
        self.recv_dir: Direction | None = None
        self.key = b""
        self.name = "?"
        # Hashes this phone just wrote, so the watcher doesn't echo them back to it.
        self.recent: dict[str, bytes] = {}
        self.execs: dict[int, executor.Running] = {}
        self.uploads: dict[int, tuple[str, bytes, int, list[bytes]]] = {}
        peer = writer.get_extra_info("peername")
        self.address = f"{peer[0]}:{peer[1]}" if peer else "?"

    # ---------- framing ----------

    async def read_frame(self, limit: int) -> bytes:
        head = await self.reader.readexactly(4)
        n = struct.unpack(">I", head)[0]
        if n > limit:
            raise WireError("oversized frame")
        body = await self.reader.readexactly(n)
        if self.recv_dir is None:
            return body
        return self.recv_dir.open(head, body)

    def write_frame(self, payload: bytes) -> None:
        """Plaintext handshake frame, or an encrypted record once keys exist."""
        if self.send_dir is None:
            self.writer.write(struct.pack(">I", len(payload)) + payload)
            return
        head = struct.pack(">I", len(payload) + 16)
        self.writer.write(head + self.send_dir.seal(head, payload))

    async def send(self, type_: int, id_: int, body: bytes) -> None:
        if self.writer.is_closing():
            return
        self.write_frame(P.encode(type_, id_, body))
        await self.writer.drain()

    # ---------- handshake ----------

    async def handshake(self) -> None:
        srv = self.server
        hello = await self.read_frame(P.HANDSHAKE_MAX)
        r = Reader(hello)
        if r.raw(4) != P.MAGIC or r.u8() != P.PROTOCOL_VERSION:
            raise AuthError("not a HarmonyCode Link client, or another protocol version")
        mode = r.u8()
        ce = r.raw(32)
        r.raw(16)
        eph = Ephemeral()
        sh = Writer().raw(P.MAGIC).u8(P.PROTOCOL_VERSION).raw(eph.public).raw(random_bytes(16)).raw(srv.identity.public).done()
        h1 = sha256(sha256(P.LABEL), hello, sh)
        self.write_frame(sh + srv.identity.sign(h1))
        await self.writer.drain()
        prk = hmac_sha256(h1, eph.agree(ce))
        self.recv_dir = Direction(hmac_sha256(prk, b"c2s\x01"))
        self.send_dir = Direction(hmac_sha256(prk, b"s2c\x01"))
        auth = Reader(await self.read_frame(P.MAX_RECORD_BYTES))
        cpk = auth.raw(32)
        name = auth.str_()[:64]
        sig = auth.raw(64)
        proof = auth.bytes_()
        h2 = sha256(h1, b"client")
        if not ed25519_verify(cpk, sig, h2):
            raise AuthError("the phone's signature is invalid")
        if mode == P.MODE_PAIR:
            if not srv.pairing.check(h2, proof):
                raise AuthError("The pairing code is wrong or expired. Scan the current QR code again.")
            srv.trust.add(cpk, name)
            srv.emit("devices", None)
            srv.emit("log", f"Paired with {name}")
            srv.emit("pairing", None)
        elif not srv.trust.is_trusted(cpk):
            raise AuthError("This phone is not paired with the desktop. Pair it again from the QR code.")
        srv.trust.seen(cpk)
        self.key = cpk
        self.name = name
        self.write_frame(Writer().u8(P.AUTH_OK).str_(srv.name).str_(srv.workspace.root.name).str_(platform.system())
                         .str_(socket.gethostname()).done())
        await self.writer.drain()

    async def fail(self, reason: str) -> None:
        try:
            if self.send_dir is not None:
                self.write_frame(Writer().u8(P.AUTH_FAIL).str_(reason).done())
                await self.writer.drain()
        except (ConnectionError, OSError):
            pass

    # ---------- messages ----------

    async def serve(self) -> None:
        while True:
            m = P.decode(await self.read_frame(P.MAX_RECORD_BYTES + 16))
            await self.dispatch(m)

    async def dispatch(self, m: P.Message) -> None:
        r = m.reader()
        if m.type == P.PING:
            await self.send(P.PONG, m.id, m.body)
        elif m.type == P.LIST:
            asyncio.ensure_future(self.on_list(m.id, r.str_()))
        elif m.type == P.GET:
            asyncio.ensure_future(self.on_get(m.id, r.str_()))
        elif m.type == P.PUT:
            await self.on_put(m.id, r)
        elif m.type == P.DELETE:
            await self.on_delete(m.id, r.str_(), r.bytes_())
        elif m.type == P.EXEC:
            asyncio.ensure_future(self.on_exec(m.id, r.str_(), r.str_(), r.u32()))
        elif m.type == P.KILL:
            job = self.execs.get(r.u32())
            if job is not None:
                job.kill()
        else:
            await self.send(P.ERROR, m.id, Writer().str_(f"unknown message {m.type}").done())

    async def error(self, id_: int, text: str) -> None:
        await self.send(P.ERROR, id_, Writer().str_(text).done())

    async def on_list(self, id_: int, prefix: str) -> None:
        try:
            entries = await asyncio.to_thread(self.server.workspace.list, prefix)
            await self.send(P.ENTRIES, id_, P.entries_body(entries))
        except PathRefused as e:
            await self.error(id_, str(e))

    async def on_get(self, id_: int, rel: str) -> None:
        ws = self.server.workspace
        try:
            entry = await asyncio.to_thread(ws.stat_entry, rel)
            if entry is None:
                await self.error(id_, f"{rel}: no such file")
                return
            if entry.size > P.MAX_FILE_BYTES:
                await self.error(id_, f"{rel} is too large to sync")
                return
            data = await asyncio.to_thread(ws.read, rel)
        except (PathRefused, OSError) as e:
            await self.error(id_, str(e))
            return
        h = sha256(data)
        offset = 0
        while True:
            chunk = data[offset:offset + P.CHUNK_BYTES]
            final = offset + len(chunk) >= len(data)
            await self.send(P.DATA, id_, Writer().str_(rel).u64(len(data)).u64(offset).boolean(final).bytes_(h)
                            .bytes_(chunk).done())
            offset += len(chunk)
            if final:
                break

    async def result(self, id_: int, status: int, message: str, h: bytes) -> None:
        await self.send(P.RESULT, id_, Writer().u8(status).str_(message).bytes_(h).done())

    async def on_put(self, id_: int, r: Reader) -> None:
        rel = r.str_()
        base = r.bytes_()
        total = r.u64()
        r.u64()  # offset: chunks arrive in order over one connection
        final = r.boolean()
        chunk = r.bytes_()
        state = self.uploads.get(id_)
        if state is None:
            if total > P.MAX_FILE_BYTES:
                await self.result(id_, P.STATUS_REFUSED, "file too large", P.ZERO_HASH)
                return
            state = (rel, base, total, [])
            self.uploads[id_] = state
        state[3].append(chunk)
        if not final:
            return
        del self.uploads[id_]
        data = b"".join(state[3])
        if len(data) != total:
            await self.result(id_, P.STATUS_ERROR, "incomplete upload", P.ZERO_HASH)
            return
        try:
            ok, h = await asyncio.to_thread(self.server.workspace.put, rel, base, data)
        except PathRefused as e:
            await self.result(id_, P.STATUS_REFUSED, str(e), P.ZERO_HASH)
            return
        except OSError as e:
            await self.result(id_, P.STATUS_ERROR, str(e), P.ZERO_HASH)
            return
        if ok:
            self.recent[rel] = h
            self.server.emit("log", f"{self.name}: updated {rel}")
            self.server.emit("files", [rel])
        await self.result(id_, P.STATUS_OK if ok else P.STATUS_CONFLICT, "" if ok else "changed on the desktop", h)

    async def on_delete(self, id_: int, rel: str, base: bytes) -> None:
        try:
            ok, h = await asyncio.to_thread(self.server.workspace.delete, rel, base)
        except PathRefused as e:
            await self.result(id_, P.STATUS_REFUSED, str(e), P.ZERO_HASH)
            return
        except OSError as e:
            await self.result(id_, P.STATUS_ERROR, str(e), P.ZERO_HASH)
            return
        if ok:
            self.recent[rel] = P.ZERO_HASH
            self.server.emit("log", f"{self.name}: deleted {rel}")
            self.server.emit("files", [rel])
        await self.result(id_, P.STATUS_OK if ok else P.STATUS_CONFLICT, "" if ok else "changed on the desktop", h)

    async def on_exec(self, id_: int, command: str, cwd: str, timeout_ms: int) -> None:
        try:
            folder = self.server.workspace.resolve(cwd)
            folder.mkdir(parents=True, exist_ok=True)
        except (PathRefused, OSError) as e:
            await self.error(id_, str(e))
            return
        self.server.emit("log", f"{self.name}: $ {command}")

        async def out(chunk: bytes) -> None:
            await self.send(P.OUTPUT, id_, Writer().bytes_(chunk).done())

        def started(job: executor.Running) -> None:
            self.execs[id_] = job

        try:
            code, timed_out = await executor.run(command, str(folder), timeout_ms / 1000.0, out, started)
        except OSError as e:
            await self.error(id_, f"cannot start the command: {e}")
            return
        finally:
            self.execs.pop(id_, None)
        await self.send(P.EXIT, id_, Writer().i32(code).boolean(timed_out).done())

    def kill_all(self) -> None:
        for job in list(self.execs.values()):
            job.kill()


class LinkServer:
    def __init__(self, workspace: Workspace, identity: Identity, trust: TrustStore, pairing: Pairing, name: str,
                 port: int, events: EventSink) -> None:
        self.workspace = workspace
        self.identity = identity
        self.trust = trust
        self.pairing = pairing
        self.name = name
        self.port = port
        self._events = events
        self.clients: set[Client] = set()
        self._server: asyncio.base_events.Server | None = None

    def emit(self, kind: str, detail: object) -> None:
        try:
            self._events(kind, detail)
        except Exception:  # never let the GUI break the server
            pass

    async def start(self) -> None:
        self._server = await asyncio.start_server(self._handle, host="0.0.0.0", port=self.port)
        self.port = self._server.sockets[0].getsockname()[1]
        await asyncio.to_thread(self.workspace.changes)  # first snapshot
        asyncio.ensure_future(self._watch())

    async def _handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        c = Client(self, reader, writer)
        try:
            await asyncio.wait_for(c.handshake(), timeout=HANDSHAKE_TIMEOUT_S)
        except AuthError as e:
            self.emit("log", f"Refused {c.address}: {e}")
            await c.fail(str(e))
            writer.close()
            return
        except (asyncio.TimeoutError, asyncio.IncompleteReadError, ConnectionError, OSError, WireError, ValueError) as e:
            self.emit("log", f"Handshake with {c.address} failed: {e or type(e).__name__}")
            writer.close()
            return
        self.clients.add(c)
        self.emit("clients", None)
        self.emit("log", f"{c.name} connected from {c.address}")
        try:
            await c.serve()
        except (asyncio.IncompleteReadError, ConnectionError, OSError):
            pass
        except (WireError, ValueError) as e:
            self.emit("log", f"Closed {c.name}: {e}")
        finally:
            c.kill_all()
            self.clients.discard(c)
            writer.close()
            self.emit("clients", None)
            self.emit("log", f"{c.name} disconnected")

    async def _watch(self) -> None:
        while True:
            await asyncio.sleep(WATCH_INTERVAL_S)
            try:
                changed = await asyncio.to_thread(self.workspace.changes)
            except OSError:
                continue
            if not changed:
                continue
            self.emit("files", [e.path for e in changed])
            for c in list(self.clients):
                mine = []
                for e in changed:
                    if c.recent.get(e.path) == e.hash:
                        del c.recent[e.path]  # this phone's own write
                        continue
                    mine.append(e)
                if mine:
                    try:
                        await c.send(P.CHANGED, 0, P.entries_body(mine))
                    except (ConnectionError, OSError):
                        pass

    def connected_names(self) -> list[str]:
        return sorted(c.name for c in self.clients)

    def disconnect(self, key_b64: str) -> None:
        from .trust import b64url
        for c in list(self.clients):
            if b64url(c.key) == key_b64:
                c.writer.close()


def default_config_dir() -> Path:
    return Path.home() / ".harmonycode-desktop"
