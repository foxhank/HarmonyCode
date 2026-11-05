"""Keys and primitives for HarmonyCode Link: Ed25519 identities, X25519, HKDF-style HMAC, AES-256-GCM."""
from __future__ import annotations

import hashlib
import hmac
import os
import stat
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.exceptions import InvalidSignature, InvalidTag

RAW = serialization.Encoding.Raw
RAW_PUB = serialization.PublicFormat.Raw
RAW_PRIV = serialization.PrivateFormat.Raw
NO_ENC = serialization.NoEncryption()


def sha256(*parts: bytes) -> bytes:
    h = hashlib.sha256()
    for p in parts:
        h.update(p)
    return h.digest()


def hmac_sha256(key: bytes, data: bytes) -> bytes:
    return hmac.new(key, data, hashlib.sha256).digest()


def random_bytes(n: int) -> bytes:
    return os.urandom(n)


def constant_eq(a: bytes, b: bytes) -> bool:
    return hmac.compare_digest(a, b)


class Identity:
    """The desktop's long-term Ed25519 key, kept in a file only its owner can read."""

    def __init__(self, key: Ed25519PrivateKey) -> None:
        self._key = key
        self.public = key.public_key().public_bytes(RAW, RAW_PUB)

    @staticmethod
    def load_or_create(path: Path) -> "Identity":
        if path.exists():
            return Identity(Ed25519PrivateKey.from_private_bytes(path.read_bytes()))
        key = Ed25519PrivateKey.generate()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(key.private_bytes(RAW, RAW_PRIV, NO_ENC))
        try:
            os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
        except OSError:
            pass  # Windows: the profile folder is already private
        return Identity(key)

    def sign(self, data: bytes) -> bytes:
        return self._key.sign(data)


def ed25519_verify(public: bytes, signature: bytes, data: bytes) -> bool:
    try:
        Ed25519PublicKey.from_public_bytes(public).verify(signature, data)
        return True
    except (InvalidSignature, ValueError):
        return False


class Ephemeral:
    """A per-connection X25519 key pair."""

    def __init__(self) -> None:
        self._key = X25519PrivateKey.generate()
        self.public = self._key.public_key().public_bytes(RAW, RAW_PUB)

    def agree(self, peer: bytes) -> bytes:
        return self._key.exchange(X25519PublicKey.from_public_bytes(peer))


class Direction:
    """AES-256-GCM for one direction, with a counter nonce: 4 zero bytes || u64 big-endian."""

    def __init__(self, key: bytes) -> None:
        self._aead = AESGCM(key)
        self._counter = 0

    def _nonce(self) -> bytes:
        n = b"\x00\x00\x00\x00" + self._counter.to_bytes(8, "big")
        self._counter += 1
        return n

    def seal(self, aad: bytes, plain: bytes) -> bytes:
        return self._aead.encrypt(self._nonce(), plain, aad)

    def open(self, aad: bytes, sealed: bytes) -> bytes:
        try:
            return self._aead.decrypt(self._nonce(), sealed, aad)
        except InvalidTag as e:
            raise ValueError("message failed authentication") from e
