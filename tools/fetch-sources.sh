#!/usr/bin/env bash
#
# Copyright (c) 2026 <copyright holder>
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Mirror the AOSP and FreeBSD sources listed in config/sources.list into src/.
# AOSP projects are pinned to the exact commit recorded in the Android build
# manifest, so native code is rebuilt from the same source as the prebuilt dex.
# Clones are shallow, blobless and (optionally) sparse.
#
#   tools/fetch-sources.sh            fetch everything missing
#   tools/fetch-sources.sh bionic art fetch only the named entries

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AOSP_BUILD="${AOSP_BUILD:-16373615}"
AOSP_REMOTE="${AOSP_REMOTE:-https://android.googlesource.com/}"
MANIFEST="$ROOT/src/manifests/manifest_${AOSP_BUILD}.xml"
LIST="$ROOT/config/sources.list"

[[ -f "$MANIFEST" ]] || { echo "missing $MANIFEST" >&2; exit 1; }

manifest_rev() {
	python3 - "$MANIFEST" "$1" <<'EOF'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for p in root.findall("project"):
    if p.get("name") == sys.argv[2]:
        print(p.get("revision") or ""); break
EOF
}

fetch_one() {
	local name="$1" kind="$2" repo="$3" ref="$4" sparse="$5"
	local dir="$ROOT/src/$name" url rev

	if [[ -d "$dir/.git" ]]; then
		echo "== $name: present ($(git -C "$dir" rev-parse --short HEAD))"
		return
	fi
	case "$kind" in
	aosp)
		url="${AOSP_REMOTE}${repo}"
		rev="$(manifest_rev "$repo")"
		[[ -n "$rev" ]] || { echo "$repo not in manifest" >&2; return 1; }
		;;
	freebsd)
		url="$repo"
		rev="$ref"
		;;
	*)
		echo "unknown kind $kind" >&2; return 1 ;;
	esac

	echo "== $name: $url @ $rev"
	git init -q "$dir"
	git -C "$dir" remote add origin "$url"
	if [[ "$sparse" != "-" ]]; then
		git -C "$dir" sparse-checkout set --cone ${sparse//,/ }
	fi
	git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$rev"
	git -C "$dir" checkout -q FETCH_HEAD
	echo "   $(git -C "$dir" rev-parse --short HEAD)  $(du -sh "$dir" | cut -f1)"
}

want=" $* "
while read -r name kind repo ref sparse; do
	[[ -z "$name" || "$name" == \#* ]] && continue
	[[ $# -eq 0 || "$want" == *" $name "* ]] || continue
	fetch_one "$name" "$kind" "$repo" "$ref" "$sparse"
done < "$LIST"
