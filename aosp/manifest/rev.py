#!/usr/bin/env python3
#
# Copyright (c) 2026 <copyright holder>
#
# SPDX-License-Identifier: BSD-2-Clause
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
