"""LZ4 block format (lz4.org): the compression of HarmonyCode Link messages.

Mirrors entry/src/main/ets/core/link/Lz4.ets: greedy matching with a 64K-entry hash table.
"""

MIN_MATCH = 4
LAST_LITERALS = 5
MF_LIMIT = 12
HASH_BITS = 16
MAX_OFFSET = 65535


class Lz4Error(ValueError):
    pass


def _length(out: bytearray, n: int) -> None:
    while n >= 255:
        out.append(255)
        n -= 255
    out.append(n)


def compress(src: bytes) -> bytes:
    n = len(src)
    out = bytearray()
    table = {}
    anchor = 0
    i = 0
    match_limit = n - MF_LIMIT
    while i < match_limit:
        seq = src[i:i + 4]
        ref = table.get(seq, -1)
        table[seq] = i
        if ref < 0 or i - ref > MAX_OFFSET:
            i += 1
            continue
        length = MIN_MATCH
        end = n - LAST_LITERALS
        while i + length < end and src[ref + length] == src[i + length]:
            length += 1
        lit = i - anchor
        ml = length - MIN_MATCH
        out.append((min(lit, 15) << 4) | min(ml, 15))
        if lit >= 15:
            _length(out, lit - 15)
        out += src[anchor:i]
        off = i - ref
        out.append(off & 0xFF)
        out.append(off >> 8)
        if ml >= 15:
            _length(out, ml - 15)
        i += length
        anchor = i
        if i < match_limit:
            table[src[i - 2:i + 2]] = i - 2
    lit = n - anchor
    out.append(min(lit, 15) << 4)
    if lit >= 15:
        _length(out, lit - 15)
    out += src[anchor:]
    return bytes(out)


def decompress(src: bytes, raw_length: int) -> bytes:
    dst = bytearray()
    s = 0
    n = len(src)
    while s < n:
        token = src[s]
        s += 1
        lit = token >> 4
        if lit == 15:
            b = 255
            while b == 255:
                if s >= n:
                    raise Lz4Error("truncated literal length")
                b = src[s]
                s += 1
                lit += b
        if s + lit > n or len(dst) + lit > raw_length:
            raise Lz4Error("literals overrun")
        dst += src[s:s + lit]
        s += lit
        if s >= n:
            break
        if s + 2 > n:
            raise Lz4Error("truncated offset")
        off = src[s] | (src[s + 1] << 8)
        s += 2
        if off == 0 or off > len(dst):
            raise Lz4Error("bad offset")
        ml = token & 15
        if ml == 15:
            b = 255
            while b == 255:
                if s >= n:
                    raise Lz4Error("truncated match length")
                b = src[s]
                s += 1
                ml += b
        ml += MIN_MATCH
        if len(dst) + ml > raw_length:
            raise Lz4Error("match overrun")
        start = len(dst) - off
        if off >= ml:
            dst += dst[start:start + ml]
        else:
            for k in range(ml):  # overlapping copy
                dst.append(dst[start + k])
    if len(dst) != raw_length:
        raise Lz4Error("size mismatch")
    return bytes(dst)
