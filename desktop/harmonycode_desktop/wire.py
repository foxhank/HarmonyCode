"""Big-endian wire encoding shared by the handshake and messages (docs/desktop-link.md)."""
from __future__ import annotations

import struct


class WireError(ValueError):
    pass


class Writer:
    def __init__(self) -> None:
        self._parts: list[bytes] = []

    def u8(self, v: int) -> "Writer":
        self._parts.append(struct.pack(">B", v))
        return self

    def boolean(self, v: bool) -> "Writer":
        return self.u8(1 if v else 0)

    def u32(self, v: int) -> "Writer":
        self._parts.append(struct.pack(">I", v))
        return self

    def i32(self, v: int) -> "Writer":
        self._parts.append(struct.pack(">i", v))
        return self

    def u64(self, v: int) -> "Writer":
        self._parts.append(struct.pack(">Q", v))
        return self

    def raw(self, b: bytes) -> "Writer":
        self._parts.append(bytes(b))
        return self

    def bytes_(self, b: bytes) -> "Writer":
        return self.u32(len(b)).raw(b)

    def str_(self, s: str) -> "Writer":
        return self.bytes_(s.encode("utf-8"))

    def done(self) -> bytes:
        return b"".join(self._parts)


class Reader:
    def __init__(self, data: bytes, offset: int = 0) -> None:
        self._b = memoryview(data)
        self._o = offset

    def _take(self, n: int) -> bytes:
        if self._o + n > len(self._b):
            raise WireError("truncated message")
        v = bytes(self._b[self._o:self._o + n])
        self._o += n
        return v

    @property
    def remaining(self) -> int:
        return len(self._b) - self._o

    def u8(self) -> int:
        return self._take(1)[0]

    def boolean(self) -> bool:
        return self.u8() != 0

    def u32(self) -> int:
        return struct.unpack(">I", self._take(4))[0]

    def u64(self) -> int:
        return struct.unpack(">Q", self._take(8))[0]

    def raw(self, n: int) -> bytes:
        return self._take(n)

    def bytes_(self) -> bytes:
        return self._take(self.u32())

    def str_(self) -> str:
        return self.bytes_().decode("utf-8")

    def rest(self) -> bytes:
        return self._take(self.remaining)
