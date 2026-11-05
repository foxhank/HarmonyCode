"""The desktop's workspace folder: safe paths, a hash cache, guarded writes and a change watcher."""
from __future__ import annotations

import hashlib
import os
import threading
from dataclasses import dataclass
from pathlib import Path

from .protocol import IGNORED_DIRS, ZERO_HASH, Entry


class PathRefused(ValueError):
    pass


@dataclass
class _Stat:
    size: int
    mtime_ns: int
    hash: bytes


class Workspace:
    """
    Files under one root. Every protocol path goes through `resolve`, which refuses anything that
    could leave the root. Hashes are cached by (size, mtime) so scans stay cheap.
    """

    def __init__(self, root: Path) -> None:
        self.root = root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()
        self._cache: dict[str, _Stat] = {}
        self._snapshot: dict[str, _Stat] | None = None

    # ---------- paths ----------

    def resolve(self, rel: str) -> Path:
        if not isinstance(rel, str) or "\x00" in rel or "\\" in rel:
            raise PathRefused("invalid path")
        parts = [p for p in rel.split("/") if p not in ("", ".")]
        if rel.startswith("/") or any(p == ".." for p in parts) or (parts and ":" in parts[0]):
            raise PathRefused("path outside the workspace")
        target = self.root.joinpath(*parts) if parts else self.root
        real = Path(os.path.realpath(target))
        if real != self.root and self.root not in real.parents:
            raise PathRefused("path outside the workspace")
        return target

    def rel_of(self, path: Path) -> str:
        return path.relative_to(self.root).as_posix()

    # ---------- reading ----------

    def _hash_file(self, path: Path) -> bytes:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        return h.digest()

    def stat_entry(self, rel: str) -> Entry | None:
        path = self.resolve(rel)
        try:
            st = path.stat()
        except OSError:
            return None
        if not path.is_file():
            return None
        return Entry(rel, st.st_size, st.st_mtime_ns // 1_000_000, self._cached_hash(rel, path, st))

    def _cached_hash(self, rel: str, path: Path, st: os.stat_result) -> bytes:
        with self._lock:
            c = self._cache.get(rel)
            if c is not None and c.size == st.st_size and c.mtime_ns == st.st_mtime_ns:
                return c.hash
        h = self._hash_file(path)
        with self._lock:
            self._cache[rel] = _Stat(st.st_size, st.st_mtime_ns, h)
        return h

    def current_hash(self, rel: str) -> bytes:
        e = self.stat_entry(rel)
        return e.hash if e is not None else ZERO_HASH

    def _walk(self, prefix: str) -> dict[str, os.stat_result]:
        """rel path -> stat for every file under prefix (dependency/build folders skipped)."""
        base = self.resolve(prefix)
        out: dict[str, os.stat_result] = {}
        if not base.is_dir():
            return out
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in IGNORED_DIRS and not os.path.islink(os.path.join(dirpath, d))]
            for name in filenames:
                if name.endswith(".hclink-tmp"):
                    continue  # a write in progress
                full = os.path.join(dirpath, name)
                try:
                    st = os.stat(full)
                except OSError:
                    continue
                rel = Path(full).relative_to(self.root).as_posix()
                out[rel] = st
        return out

    def list(self, prefix: str) -> list[Entry]:
        out = []
        for rel, st in sorted(self._walk(prefix).items()):
            try:
                h = self._cached_hash(rel, self.root / rel, st)
            except OSError:
                continue
            out.append(Entry(rel, st.st_size, st.st_mtime_ns // 1_000_000, h))
        return out

    def read(self, rel: str) -> bytes:
        return self.resolve(rel).read_bytes()

    # ---------- guarded writes ----------

    def put(self, rel: str, base: bytes, data: bytes) -> tuple[bool, bytes]:
        """Writes if the current hash is `base`. Returns (written, hash now)."""
        path = self.resolve(rel)
        with self._lock:
            current = self.current_hash(rel)
            if current != base:
                return False, current
            path.parent.mkdir(parents=True, exist_ok=True)
            tmp = path.with_name(f".{path.name}.hclink-tmp")
            tmp.write_bytes(data)
            os.replace(tmp, path)
            st = path.stat()
            h = hashlib.sha256(data).digest()
            self._cache[rel] = _Stat(st.st_size, st.st_mtime_ns, h)
            return True, h

    def delete(self, rel: str, base: bytes) -> tuple[bool, bytes]:
        path = self.resolve(rel)
        with self._lock:
            current = self.current_hash(rel)
            if current != base:
                return False, current
            if current != ZERO_HASH:
                path.unlink()
                self._cache.pop(rel, None)
                self._prune_dirs(path.parent)
            return True, ZERO_HASH

    def _prune_dirs(self, d: Path) -> None:
        """Removes folders a deletion left empty (up to the root)."""
        while d != self.root and self.root in d.parents:
            try:
                d.rmdir()
            except OSError:
                return
            d = d.parent

    # ---------- watching ----------

    def changes(self) -> list[Entry]:
        """What changed since the previous call (the first call only takes a snapshot)."""
        files = self._walk("")
        now: dict[str, _Stat] = {}
        changed: list[Entry] = []
        prev = self._snapshot
        for rel, st in files.items():
            old = prev.get(rel) if prev is not None else None
            if old is not None and old.size == st.st_size and old.mtime_ns == st.st_mtime_ns:
                now[rel] = old
                continue
            try:
                h = self._cached_hash(rel, self.root / rel, st)
            except OSError:
                continue
            now[rel] = _Stat(st.st_size, st.st_mtime_ns, h)
            if prev is not None and (old is None or old.hash != h):
                changed.append(Entry(rel, st.st_size, st.st_mtime_ns // 1_000_000, h))
        if prev is not None:
            for rel in prev.keys() - now.keys():
                changed.append(Entry(rel, 0, 0, ZERO_HASH, deleted=True))
        self._snapshot = now
        return changed
