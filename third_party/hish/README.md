# hiSH runtime (prebuilt)

HarmonyCode runs Linux environments with [hiSH](https://github.com/harmoninux/hiSH) (MIT License):
QEMU built for HarmonyOS, an arm64 Linux kernel and an Alpine Linux root filesystem.

These binaries are not stored in git. `scripts/fetch-hish.ps1` (run by `build.ps1`) downloads the
hiSH release pinned in `hish.lock.json`, checks its SHA-256, and copies:

| From the release HAP | To |
|---|---|
| `libs/<abi>/libqemu-system-aarch64.so`, `libslirp.so.0` | `hish/libs/<abi>/` |
| `resources/rawfile/vm/kernel_aarch64`, `efi-virtio.rom` | `hish/src/main/resources/rawfile/hish/` |
| `resources/rawfile/vm/rootfs_aarch64.qcow2` | `hish/src/main/resources/rawfile/hish/alpine.qcow2` |

The download is cached in `third_party/hish/cache/`. To move to a newer hiSH release, update `release`,
`url` and `sha256` in `hish.lock.json`.

Other distributions (Ubuntu) are downloaded by the app at runtime from
[HiSH-Linux-Image](https://github.com/harmoninux/HiSH-Linux-Image); URLs and checksums are in
`entry/src/main/resources/rawfile/catalog/catalog.json`.

## Licenses and sources

- hiSH: MIT — https://github.com/harmoninux/hiSH
- QEMU (`libqemu-system-aarch64.so`): GPL-2.0 — source: https://github.com/harmoninux/qemu (branch `hish-libqemu`)
- libslirp: BSD-3-Clause — built from QEMU's `subprojects/slirp`
- Linux kernel: GPL-2.0 — config: https://github.com/harmoninux/linux-config
- Alpine Linux root filesystem: packages under their own licenses — https://alpinelinux.org
