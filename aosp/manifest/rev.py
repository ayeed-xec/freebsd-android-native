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
# rev.py -- print the pinned revision of AOSP projects from a repo manifest
# (plan §9.1).  It prints one line for each project, in argument order.
#
#   python3.11 -I aosp/manifest/rev.py <manifest.xml> [-v] <project>...
#
# A project is a googlesource name such as platform/bionic.  -v prints
# "<revision> <path> <name>".  A project without a revision attribute gets
# the revision of <default>.  Exit 1 if a project is not in the manifest.
#
# The manifest is a trusted input: check its MD5 against plan §9.1 first
# (aosp/fetch.py does this).

import sys
import xml.etree.ElementTree as ET


class ManifestError(Exception):
    pass


def load(manifest):
    """Return {name: (path, revision)} for each <project> of a manifest."""
    root = ET.parse(manifest).getroot()
    default = root.find("default")
    default_rev = default.get("revision") if default is not None else None
    projects = {}
    for p in root.iter("project"):
        name = p.get("name")
        rev = p.get("revision", default_rev)
        if name is None or rev is None:
            raise ManifestError(f"{manifest}: project without name or revision")
        projects[name] = (p.get("path", name), rev)
    return projects


def main(argv):
    args = argv[1:]
    verbose = "-v" in args
    args = [a for a in args if a != "-v"]
    if len(args) < 2:
        print("usage: rev.py <manifest.xml> [-v] <project>...", file=sys.stderr)
        return 2
    try:
        projects = load(args[0])
    except (OSError, ET.ParseError, ManifestError) as e:
        print(f"rev.py: {e}", file=sys.stderr)
        return 1
    status = 0
    for name in args[1:]:
        if name not in projects:
            print(f"rev.py: {name}: not in {args[0]}", file=sys.stderr)
            status = 1
            continue
        path, rev = projects[name]
        print(f"{rev} {path} {name}" if verbose else rev)
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv))
