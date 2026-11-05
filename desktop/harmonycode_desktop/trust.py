"""Paired phones and the one-time pairing secret shown in the QR code."""
from __future__ import annotations

import base64
import json
import socket
import threading
import time
import urllib.parse
from dataclasses import asdict, dataclass
from pathlib import Path

from .crypto import constant_eq, hmac_sha256, random_bytes

PAIRING_TTL_S = 600


def b64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode("ascii").rstrip("=")


def fingerprint(public: bytes) -> str:
    """Short, human-comparable form of a key."""
    import hashlib
    return b64url(hashlib.sha256(public).digest()[:12])


@dataclass
class Device:
    key: str  # base64url Ed25519 public key
    name: str
    paired_at: float
    last_seen: float = 0.0


class TrustStore:
    """Phones allowed to connect. Persisted as JSON next to the identity key."""

    def __init__(self, path: Path) -> None:
        self._path = path
        self._lock = threading.Lock()
        self._devices: dict[str, Device] = {}
        if path.exists():
            try:
                for d in json.loads(path.read_text("utf-8")):
                    self._devices[d["key"]] = Device(**d)
            except (ValueError, KeyError, TypeError):
                self._devices = {}

    def devices(self) -> list[Device]:
        with self._lock:
            return sorted(self._devices.values(), key=lambda d: -d.last_seen)

    def is_trusted(self, public: bytes) -> bool:
        with self._lock:
            return b64url(public) in self._devices

    def add(self, public: bytes, name: str) -> None:
        with self._lock:
            now = time.time()
            self._devices[b64url(public)] = Device(b64url(public), name[:64] or "Phone", now, now)
            self._save()

    def seen(self, public: bytes) -> None:
        with self._lock:
            d = self._devices.get(b64url(public))
            if d is not None:
                d.last_seen = time.time()
                self._save()

    def remove(self, key: str) -> None:
        with self._lock:
            self._devices.pop(key, None)
            self._save()

    def _save(self) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self._path.with_suffix(".tmp")
        tmp.write_text(json.dumps([asdict(d) for d in self._devices.values()], indent=1), "utf-8")
        tmp.replace(self._path)


class Pairing:
    """The current one-time secret: 128 bits, valid for 10 minutes, used at most once."""

    def __init__(self, fixed_secret: bytes | None = None) -> None:
        self._lock = threading.Lock()
        self._fixed = fixed_secret
        self._secret = b""
        self._expires = 0.0
        self.renew()

    def renew(self) -> None:
        with self._lock:
            self._secret = self._fixed if self._fixed is not None else random_bytes(16)
            self._expires = time.time() + PAIRING_TTL_S

    def current(self) -> tuple[bytes, float]:
        with self._lock:
            if time.time() > self._expires:
                self._secret = self._fixed if self._fixed is not None else random_bytes(16)
                self._expires = time.time() + PAIRING_TTL_S
            return self._secret, self._expires

    def check(self, transcript: bytes, proof: bytes) -> bool:
        """Verifies a phone's proof and burns the secret on success."""
        with self._lock:
            if not self._secret or time.time() > self._expires:
                return False
            ok = constant_eq(hmac_sha256(self._secret, transcript), proof)
            if ok:
                self._secret = b""  # single use; the GUI shows a fresh code
                self._expires = 0.0
            return ok


def lan_addresses() -> list[str]:
    """IPv4 addresses phones on the LAN can reach, the default route's first."""
    found: list[str] = []
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 1))  # no packet is sent; picks the outgoing interface
            found.append(s.getsockname()[0])
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if ip not in found:
                found.append(ip)
    except OSError:
        pass
    usable = [ip for ip in found if not ip.startswith("127.") and not ip.startswith("169.254.")]
    return usable or ["127.0.0.1"]


def pairing_uri(addresses: list[str], port: int, server_key: bytes, secret: bytes, name: str) -> str:
    query = urllib.parse.urlencode({
        "v": "1",
        "a": ",".join(f"{a}:{port}" for a in addresses),
        "k": b64url(server_key),
        "s": b64url(secret),
        "n": name,
    }, quote_via=urllib.parse.quote)
    return "hclink://pair?" + query
