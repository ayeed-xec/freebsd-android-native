#!/bin/sh
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
# Mirror the AOSP and FreeBSD sources listed in config/sources.list into src/.
# AOSP projects are pinned to the exact commit recorded in the Android build
# manifest, so native code is rebuilt from the same source as the prebuilt dex.
# Clones are shallow, blobless and (optionally) sparse.
#
#   tools/fetch-sources.sh            fetch everything missing
#   tools/fetch-sources.sh bionic art fetch only the named entries

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AOSP_BUILD="${AOSP_BUILD:-16373615}"
AOSP_REMOTE="${AOSP_REMOTE:-https://android.googlesource.com/}"
MANIFEST="$ROOT/src/manifests/manifest_${AOSP_BUILD}.xml"
LIST="$ROOT/config/sources.list"

[ -f "$MANIFEST" ] || { echo "missing $MANIFEST" >&2; exit 1; }

manifest_rev() {
	sh "$ROOT/aosp/manifest/rev.sh" "$MANIFEST" "$1" 2>/dev/null || true
}

fetch_one() {
	local name="$1" kind="$2" repo="$3" ref="$4" sparse="$5"
	local dir="$ROOT/src/$name" url rev

	if [ -d "$dir/.git" ]; then
		echo "== $name: present ($(git -C "$dir" rev-parse --short HEAD))"
		return
	fi
	case "$kind" in
	aosp)
		url="${AOSP_REMOTE}${repo}"
		rev="$(manifest_rev "$repo")"
		[ -n "$rev" ] || { echo "$repo not in manifest" >&2; return 1; }
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
	if [ "$sparse" != "-" ]; then
		git -C "$dir" sparse-checkout set --cone $(echo "$sparse" | tr , " ")
	fi
	git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$rev"
	git -C "$dir" checkout -q FETCH_HEAD
	echo "   $(git -C "$dir" rev-parse --short HEAD)  $(du -sh "$dir" | cut -f1)"
}

want=" $* "
while read -r name kind repo ref sparse; do
	case $name in
	''|\#*)	continue ;;
	esac
	if [ $# -ne 0 ]; then
		case $want in
		*" $name "*) ;;
		*)	continue ;;
		esac
	fi
	fetch_one "$name" "$kind" "$repo" "$ref" "$sparse"
done < "$LIST"
