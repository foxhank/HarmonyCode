"""HarmonyCode Link message codec (docs/desktop-link.md section 6)."""
from __future__ import annotations

from dataclasses import dataclass

from . import lz4
from .wire import Reader, Writer

PROTOCOL_VERSION = 1
DEFAULT_PORT = 47110
MAGIC = b"HCL1"
LABEL = b"HCLINK-v1"
MODE_PAIR = 1
MODE_RESUME = 2
AUTH_OK = 0
AUTH_FAIL = 1
ZERO_HASH = bytes(32)
CHUNK_BYTES = 512 * 1024
MAX_FILE_BYTES = 256 * 1024 * 1024
MAX_RECORD_BYTES = 1024 * 1024 + 64 * 1024
HANDSHAKE_MAX = 4096
FLAG_LZ4 = 1

PING = 0x01
PONG = 0x02
LIST = 0x10
ENTRIES = 0x11
GET = 0x12
DATA = 0x13
PUT = 0x14
RESULT = 0x15
DELETE = 0x16
CHANGED = 0x17
EXEC = 0x20
OUTPUT = 0x21
EXIT = 0x22
KILL = 0x23
ERROR = 0x7F

STATUS_OK = 0
STATUS_CONFLICT = 1
STATUS_REFUSED = 2
STATUS_ERROR = 3

# Dependency and build folders are never synced.
IGNORED_DIRS = frozenset([".git", "node_modules", "target", "build", ".venv", "venv", "__pycache__", "oh_modules",
                          ".hvigor", "dist", ".idea", ".gradle", ".next", ".cache"])


@dataclass
class Entry:
    path: str
    size: int
    mtime: int
    hash: bytes
    deleted: bool = False

    def write(self, w: Writer) -> None:
        w.str_(self.path).u64(self.size).u64(self.mtime).bytes_(self.hash).boolean(self.deleted)


@dataclass
class Message:
    type: int
    id: int
    body: bytes

    def reader(self) -> Reader:
        return Reader(self.body)


def encode(type_: int, id_: int, body: bytes) -> bytes:
    flags = 0
    payload = body
    if len(body) >= 64:
        packed = lz4.compress(body)
        if len(packed) + 4 < len(body) - (len(body) >> 4):
            payload = Writer().u32(len(body)).raw(packed).done()
            flags |= FLAG_LZ4
    return Writer().u8(type_).u8(flags).u32(id_).raw(payload).done()


def decode(plain: bytes) -> Message:
    r = Reader(plain)
    type_ = r.u8()
    flags = r.u8()
    id_ = r.u32()
    body = r.rest()
    if flags & FLAG_LZ4:
        br = Reader(body)
        raw = br.u32()
        if raw > MAX_RECORD_BYTES * 4:
            raise ValueError("compressed message too large")
        body = lz4.decompress(br.rest(), raw)
    return Message(type_, id_, body)


def entries_body(entries: list[Entry]) -> bytes:
    w = Writer().u32(len(entries))
    for e in entries:
        e.write(w)
    return w.done()
