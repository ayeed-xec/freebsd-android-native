#!/usr/bin/env python3
#
# Copyright (c) 2026 Ayeed Shaikh <Ayeed.AI10@race.reva.edu.in>
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
# fetch.py -- fetch AOSP projects at the revisions of the pinned manifest
# (plan §9.1): blobless, depth 1, sparse, fetch by SHA.
#
#   python3.11 -I aosp/fetch.py [--week N] [--dest DIR] [--dry-run] [ROW...]
#   python3.11 -I aosp/fetch.py --project NAME[:DIR,...] [--project ...]
#   python3.11 -I aosp/fetch.py --list
#
# ROW is a row number of the plan §9.1 table (1-19).  With no ROW and no
# --project, the rows of --week (default 1) are fetched.  --project fetches a
# manifest project that is not in the table (row "+", no budget), whole or
# only the directories DIR.  DIR defaults to $AOSP_SRC, else ~/aosp.
# Each project goes to DIR/<manifest path>.  For each project the tool checks
# that HEAD equals the manifest revision, then prints du -sk against the plan
# budget.  It falls back to the android-17.0.0_r1 tag only if the server
# refuses the fetch by SHA.  Run it again to repair or to check a tree: a
# project that is already at its revision with the same sparse set is skipped.
#
# Exit 0 if every HEAD equals its revision, else 1.  A row over its budget is
# reported but is not an error.

import argparse
import hashlib
import importlib.util
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MANIFEST = HERE / "manifest" / "manifest_16373615.xml"
MANIFEST_MD5 = "b3a6e0f1bc95a05af277a13bf5dd2b8c"
REMOTE = "https://android.googlesource.com/"
FALLBACK_REF = "refs/tags/android-17.0.0_r1"
SHA1 = re.compile(r"^[0-9a-f]{40}$")


class Project:
    def __init__(self, name, paths=None, exclude=None):
        self.name = name
        self.paths = paths              # None: the whole project
        self.exclude = exclude or []    # directories under paths to leave out

    def patterns(self):
        """Non-cone sparse patterns: top-level files, paths, minus exclude."""
        pats = ["/*", "!/*/"]
        pats += [f"/{p}/" for p in self.paths]
        pats += [f"!/{x}/" for x in self.exclude]
        return pats


# Plan §9.1: (row, week, budget in MB, projects).
ROWS = [
    (1, 1, 10, [Project("platform/system/libbase")]),
    (2, 1, 20, [Project("platform/system/logging",
                        ["liblog", "logd", "logcat"])]),
    (3, 1, 60, [Project("platform/system/core",
                        ["libcutils", "libutils", "include", "init", "rootdir",
                         "libprocessgroup", "property_service", "toolbox",
                         "libsystem"])]),
    (4, 1, 10, [Project("platform/system/libziparchive")]),
    (5, 1, 5, [Project("platform/system/libprocinfo")]),
    (6, 1, 15, [Project("platform/external/fmtlib", ["include", "src"])]),
    (7, 1, 80, [Project("platform/frameworks/native",
                        ["libs/binder", "cmds/servicemanager", "cmds/service",
                         "include"])]),
    (8, 1, 20, [Project("platform/system/tools/aidl")]),
    # Rev 2: the whole runtime, minus the malloc traces (about 95 MB).
    (9, 1, 100, [Project("platform/bionic",
                         ["libc", "libm", "libdl", "linker", "tests", "docs"],
                         exclude=["libc/memory/replay/traces"])]),
    (10, 1, 50, [Project("platform/libcore",
                         ["luni/src/main/native", "ojluni/src/main/native",
                          "luni/src/main/java/android/system"])]),
    (11, 1, 10, [Project("platform/libnativehelper")]),
    (12, 2, 20, [Project("platform/build/blueprint")]),
    (13, 2, 70, [Project("platform/art",
                         ["build", "libartbase", "libdexfile", "libprofile",
                          "libelffile", "libartpalette", "runtime",
                          "sigchainlib", "dalvikvm", "libnativebridge",
                          "libnativeloader", "dexdump", "cmdline", "tools"])]),
    (14, 2, 150, [Project("platform/external/icu",
                          ["icu4c/source/common", "icu4c/source/i18n",
                           "icu4c/source/stubdata", "libicu", "libandroidicu",
                           "android_icu4c"])]),
    (15, 2, 20, [Project("platform/external/vixl", ["src"])]),
    (16, 2, 40, [Project("platform/external/zlib"),
                 Project("platform/external/lz4"),
                 Project("platform/external/lzma")]),
    # Upstream, not pinned by the manifest: the tool reports it as manual.
    (17, 2, 5, [Project("github.com/google/cpu_features")]),
    (18, 2, 150, [Project("platform/frameworks/base",
                          ["core/jni", "services/core/jni", "cmds/app_process",
                           "core/java/android/os"])]),
    # compiler-rt builtins and libunwind are not in the manifest (plan (u)).
    (19, 2, 60, [Project("platform/external/libcxx", ["src", "include"]),
                 Project("platform/external/libcxxabi", ["src", "include"]),
                 Project("platform/external/jemalloc_new")]),
]


def load_rev():
    """Import rev.py by path: python -I does not add HERE to sys.path."""
    spec = importlib.util.spec_from_file_location("rev",
                                                  HERE / "manifest" / "rev.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


class Git:
    def __init__(self, dry_run):
        self.dry_run = dry_run
        self.env = dict(os.environ, GIT_TERMINAL_PROMPT="0")

    def run(self, d, *args, check=True):
        cmd = ["git", "-C", str(d), *args]
        if self.dry_run:
            print("  $ " + " ".join(cmd))
            return subprocess.CompletedProcess(cmd, 0, "", "")
        r = subprocess.run(cmd, env=self.env, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if check and r.returncode != 0:
            raise RuntimeError(f"{' '.join(cmd)}: {r.stderr.strip()}")
        return r

    def out(self, d, *args):
        r = subprocess.run(["git", "-C", str(d), *args], env=self.env,
                           text=True, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL)
        return r.stdout.strip() if r.returncode == 0 else None


def sparse_state(git, d):
    """Return (enabled, cone, patterns) of an existing repository."""
    if git.out(d, "config", "--bool", "core.sparseCheckout") != "true":
        return (False, False, [])
    cone = git.out(d, "config", "--bool", "core.sparseCheckoutCone") == "true"
    f = Path(git.out(d, "rev-parse", "--git-path", "info/sparse-checkout")
             or "")
    if not f.is_absolute():
        f = d / f
    pats = f.read_text().split() if f.is_file() else []
    return (True, cone, pats)


def wanted_sparse(proj):
    if proj.paths is None:
        return (False, False, [])
    if proj.exclude:
        return (True, False, proj.patterns())
    # Cone mode writes its own patterns; compare the directory list.
    return (True, True, sorted(proj.paths))


def same_sparse(git, d, proj):
    enabled, cone, pats = sparse_state(git, d)
    w_enabled, w_cone, w_pats = wanted_sparse(proj)
    if enabled != w_enabled or cone != w_cone:
        return False
    if not enabled:
        return True
    if cone:
        listed = git.out(d, "sparse-checkout", "list")
        return sorted((listed or "").split()) == w_pats
    return pats == w_pats


def fetch_project(git, dest, proj, path, rev):
    """Fetch one project.  Return (status, head)."""
    d = dest / path
    if (d / ".git").is_dir() and git.out(d, "rev-parse", "HEAD") == rev and \
            same_sparse(git, d, proj):
        return ("present", rev)
    if not git.dry_run:
        d.mkdir(parents=True, exist_ok=True)
    git.run(d, "init", "-q")
    url = REMOTE + proj.name
    if git.out(d, "remote", "get-url", "origin") is None:
        git.run(d, "remote", "add", "origin", url)
    else:
        git.run(d, "remote", "set-url", "origin", url)
    if proj.paths is None:
        if sparse_state(git, d)[0]:
            git.run(d, "sparse-checkout", "disable")
    elif proj.exclude:
        git.run(d, "sparse-checkout", "set", "--no-cone", *proj.patterns())
    else:
        git.run(d, "sparse-checkout", "set", "--cone", *proj.paths)
    status = "sha"
    r = git.run(d, "fetch", "-q", "--depth=1", "--filter=blob:none",
                "origin", rev, check=False)
    if r.returncode != 0:
        print(f"  {proj.name}: fetch by SHA refused: {r.stderr.strip()}",
              file=sys.stderr)
        git.run(d, "fetch", "-q", "--depth=1", "--filter=blob:none",
                "origin", FALLBACK_REF)
        status = "tag"
    git.run(d, "-c", "advice.detachedHead=false", "checkout", "-q",
            "FETCH_HEAD")
    if git.dry_run:
        return ("dry-run", rev)
    return (status, git.out(d, "rev-parse", "HEAD"))


def du_kb(path):
    r = subprocess.run(["du", "-sk", str(path)], text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return int(r.stdout.split()[0]) if r.returncode == 0 and r.stdout else 0


def main():
    ap = argparse.ArgumentParser(description="Fetch pinned AOSP projects "
                                 "(plan §9.1).")
    ap.add_argument("rows", nargs="*", type=int, metavar="ROW")
    ap.add_argument("--week", type=int, default=1)
    ap.add_argument("--dest", type=Path,
                    default=Path(os.environ.get("AOSP_SRC",
                                                Path.home() / "aosp")))
    ap.add_argument("--manifest", type=Path, default=MANIFEST)
    ap.add_argument("--md5", default=MANIFEST_MD5,
                    help="expected manifest MD5, or 'none' to skip the check")
    ap.add_argument("--project", action="append", default=[],
                    metavar="NAME[:DIR,...]",
                    help="a manifest project that is not in the table")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--list", action="store_true",
                    help="print the rows with their revisions and exit")
    args = ap.parse_args()

    if args.md5 != "none" and md5(args.manifest) != args.md5:
        print(f"fetch.py: {args.manifest}: MD5 is not {args.md5}",
              file=sys.stderr)
        return 1
    rev = load_rev()
    pins = rev.load(args.manifest)
    rows = [r for r in ROWS if (r[0] in args.rows if args.rows else
                                r[1] == args.week and not args.project)]
    if args.rows and len(rows) != len(set(args.rows)):
        print("fetch.py: a ROW is not in 1-19", file=sys.stderr)
        return 2
    for spec in args.project:
        name, _, dirs = spec.partition(":")
        rows.append(("+", 0, None,
                     [Project(name, dirs.split(",") if dirs else None)]))

    git = Git(args.dry_run)
    failed = False
    total_kb = budget_mb = 0
    if args.list:
        print(f"{'#':>2} {'project':<34} {'revision':<12} path")
    else:
        print(f"{'#':>2} {'project':<34} {'revision':<12} {'status':<8} "
              f"{'HEAD':<4} {'MB':>6} {'budget':>6}")
    for num, _, budget, projects in rows:
        row_kb = 0
        for proj in projects:
            pin = pins.get(proj.name)
            if pin is None:
                print(f"{num:>2} {proj.name:<34} {'-':<12} {'manual':<8} "
                      f"{'-':<4} {'-':>6} {'-':>6}  not in the manifest")
                continue
            path, sha = pin
            if args.list:
                print(f"{num:>2} {proj.name:<34} {sha[:12]:<12} {path}")
                continue
            if not SHA1.match(sha):
                print(f"{num:>2} {proj.name:<34} {sha:<12} not a SHA-1",
                      file=sys.stderr)
                failed = True
                continue
            try:
                status, head = fetch_project(git, args.dest, proj, path, sha)
            except (OSError, RuntimeError) as e:
                print(f"{num:>2} {proj.name:<34} {sha[:12]:<12} error: {e}",
                      file=sys.stderr)
                failed = True
                continue
            ok = head == sha
            failed |= not ok
            mark = "-" if args.dry_run else ("ok" if ok else "BAD")
            kb = 0 if args.dry_run else du_kb(args.dest / path)
            row_kb += kb
            print(f"{num:>2} {proj.name:<34} {sha[:12]:<12} {status:<8} "
                  f"{mark:<4} {kb / 1024:>6.1f} {budget or '-':>6}")
        if not args.list and not args.dry_run:
            total_kb += row_kb
            budget_mb += budget or 0
            if budget is not None and row_kb > budget * 1024:
                print(f"{num:>2} over budget: {row_kb / 1024:.1f} MB > "
                      f"{budget} MB")
    if not args.list and not args.dry_run:
        print(f"total {total_kb / 1024:.1f} MB for the rows, budget "
              f"{budget_mb} MB; du -sk {args.dest}: "
              f"{du_kb(args.dest.resolve()) / 1024:.1f} MB")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
