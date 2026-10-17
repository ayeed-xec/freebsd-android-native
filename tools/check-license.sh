#!/bin/sh
#
# Copyright (c) 2026 <copyright holder>
#
# SPDX-License-Identifier: BSD-2-Clause
#
# License gate for FreeBSD-side sources (docs/standards/kernel-style-and-licensing.md).
# Fails if a source file lacks a BSD-2-Clause SPDX header or carries GPL markers.
#
#   tools/check-license.sh [dir...]     default: kmod tests tools guest

set -eu

cd "$(dirname "$0")/.."
[ $# -gt 0 ] || set -- kmod tests tools guest

status=0
files=$(find "$@" -type f \( -name '*.c' -o -name '*.h' -o -name '*.sh' \
    -o -name '*.[1-9]' -o -name 'Makefile' \) 2>/dev/null | sort)

self="tools/check-license.sh"
for f in $files; do
	[ "$f" = "$self" ] && continue	# contains the patterns it searches for
	if ! head -n 12 "$f" | grep -q 'SPDX-License-Identifier: BSD-2-Clause'; then
		echo "missing BSD-2-Clause SPDX header: $f"
		status=1
	fi
	if grep -n -I -E 'GPL-2\.0|GPL-3\.0|GNU General Public License|MODULE_LICENSE|EXPORT_SYMBOL_GPL' \
	    "$f" >/dev/null 2>&1; then
		echo "GPL marker found: $f"
		grep -n -E 'GPL-2\.0|GPL-3\.0|GNU General Public License|MODULE_LICENSE|EXPORT_SYMBOL_GPL' \
		    "$f" | sed 's/^/    /'
		status=1
	fi
done

if [ "$status" -eq 0 ]; then
	echo "license check passed ($(echo "$files" | grep -c . || true) files)"
fi
exit "$status"
