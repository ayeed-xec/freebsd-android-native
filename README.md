# freebsd-android-native

This project runs the latest Android natively on FreeBSD. Android's native
layer (libc, linker, ART, init, binder, system services and HALs) is built as FreeBSD
programs that use FreeBSD system calls. There is no Linux kernel and no Linux
compatibility layer (the Linuxulator stays off). The Java and Kotlin framework is
OS-independent bytecode from the latest AOSP release.

```
┌──────────────────── Android (latest AOSP) ─────────────────────────┐
│ Java/Kotlin framework + apps (dex, reused from the AOSP release)    │
│ ART · system_server JNI · SurfaceFlinger · servicemanager · init    │
│ libc + linker — rebuilt as native FreeBSD ELF binaries              │
└──────────────────── FreeBSD system calls ───────┬──────────────────┘
                                                  ▼
┌──────────────────── FreeBSD 15.x kernel ───────────────────────────┐
│ binder.ko (new, BSD-2-Clause) · kqueue · eventfd/timerfd/inotify    │
│ memfd + seals · evdev · netlink · devd · rctl/cpuset · MAC · drm-kmod │
└─────────────────────────────────────────────────────────────────────┘
```

## Sources

The sources and the changes to them are in their own repositories, on a branch. Each
repository keeps its upstream license.

| Source | Repository | Branch with our changes | Base |
|---|---|---|---|
| FreeBSD | [freebsd-src](https://github.com/ayeed-xec/freebsd-src) (fork) | `android-native-15.1` | `releng/15.1`, commit `893c7c99b6` |
| AOSP `platform/art` | [platform_art](https://github.com/ayeed-xec/platform_art) | `freebsd` | branch `upstream`: the tree at `b753cf9792` |
| AOSP `platform/system/libbase` | [platform_system_libbase](https://github.com/ayeed-xec/platform_system_libbase) | `freebsd` | branch `upstream`: the tree at `fef4173e19` |
| AOSP `platform/system/logging` | [platform_system_logging](https://github.com/ayeed-xec/platform_system_logging) | `freebsd` | branch `upstream`: the tree at `d35ba62045` |

The AOSP commits are from Android 17 build 16373615. The `upstream` branch of each AOSP
repository is an import of the pinned tree, as in a FreeBSD vendor import. The
`freebsd` branch adds our changes as commits on top of it. The other AOSP projects have no
changes yet. They come from AOSP at their pinned commits.

## Get the sources

AOSP projects, with the `repo` tool and the manifest of this repository:

```bash
repo init -u https://github.com/ayeed-xec/freebsd-android-native -m default.xml
```

```bash
repo sync
```

FreeBSD:

```bash
git clone -b android-native-15.1 https://github.com/ayeed-xec/freebsd-src.git
```

`tools/fetch-sources.sh` makes small partial mirrors of the same AOSP and FreeBSD sources
in `src/`, from the list in `config/sources.list`.

## This repository

| Path | Purpose |
|---|---|
| `default.xml` | The `repo` manifest of the AOSP projects |
| `config/toolchain/` | The clang configuration for the `aarch64-unknown-freebsd15-android37` target, and a CMake file for host tools |
| `config/sources.list` | The source mirrors for `tools/fetch-sources.sh` |
| `aosp/` | `fetch.sh` and the AOSP manifest of build 16373615 |
| `tools/` | `check-license.sh` (license check) and `fetch-sources.sh` |

## Status

- M0, foundations and risk probes: done. The FreeBSD 15.1 probes found the kernel and
  libc gaps that the port must close.
- The first changes are in the AOSP `freebsd` branches: libbase, liblog and libartbase
  build on FreeBSD.
- Next: M1, bionic libc and the linker as native FreeBSD programs. The first FreeBSD
  kernel change is a `knote_triv_copy` copy function for timerfd knotes, so that a
  `KQUEUE_CPONFORK` child keeps them.

## License

- Each FreeBSD-side file has a BSD-2-Clause header: the copyright line, the SPDX line
  and the full license text. No GPL code is used.
- AOSP files, and our changes to them, keep their AOSP licenses.
- The copyright holder of our files is Ayeed Shaikh.
