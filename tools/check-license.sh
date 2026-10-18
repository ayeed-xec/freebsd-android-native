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
# License gate for FreeBSD-side sources (docs/standards/kernel-style-and-licensing.md).
# Fails if a source file lacks a BSD-2-Clause SPDX header or the license text,
# still has the old copyright holder placeholder, or carries GPL markers.
#
#   tools/check-license.sh [dir...]     default: kmod tests tools guest
#   tools/check-license.sh -f fork [base]
#
# With -f, check the files that the fork (for example src/platform_bionic)
# adds or changes against base (default upstream), as ADR 0002 section 13
# says.  A new source file of ours gets the checks above.  A new file under
# libc/upstream-*/lib/ is imported (docs/provenance.md) and keeps its own
# license: a BSD, MIT or ISC notice, or no notice when it has only
# preprocessor lines.  A changed file keeps the license that it has.  No
# new or changed file may carry GPL markers.

set -eu

gpl='GPL-2\.0|GPL-3\.0|GNU General Public License|MODULE_LICENSE|EXPORT_SYMBOL_GPL'
permissive='SPDX-License-Identifier: (BSD-2-Clause|BSD-3-Clause|MIT|ISC)|Redistribution and use in source and binary forms|Permission to use, copy, modify|Permission is hereby granted'
status=0
self="tools/check-license.sh"

# The file types that must have our header.
is_source()
{
	case ${1##*/} in
	*.c|*.h|*.cpp|*.S|*.inc|*.sh|*.awk|*.py|*.rs|*.[1-9]|Makefile|\
	CMakeLists.txt|*.cmake|*.excluded|SYSCALLS.FREEBSD.TXT)
		return 0 ;;
	esac
	return 1
}

# check_gpl file [name]
check_gpl()
{
	if grep -n -I -E "$gpl" "$1" >/dev/null 2>&1; then
		echo "GPL marker found: ${2:-$1}"
		grep -n -E "$gpl" "$1" | sed 's/^/    /'
		status=1
	fi
}

# check_ours file [name]
check_ours()
{
	if ! head -n 12 "$1" | grep -q 'SPDX-License-Identifier: BSD-2-Clause'; then
		echo "missing BSD-2-Clause SPDX header: ${2:-$1}"
		status=1
	fi
	if ! head -n 40 "$1" |
	    grep -q 'Redistribution and use in source and binary forms'; then
		echo "missing BSD-2-Clause license text: ${2:-$1}"
		status=1
	fi
	if grep -q -F '<copyright'' holder>' "$1"; then
		echo "placeholder copyright holder: ${2:-$1}"
		status=1
	fi
	check_gpl "$@"
}

# check_imported file [name]
check_imported()
{
	if ! head -n 40 "$1" | grep -q -E "$permissive" &&
	    grep -q -v -E '^[[:space:]]*(#.*)?$' "$1"; then
		echo "imported file without a BSD, MIT or ISC notice: ${2:-$1}"
		status=1
	fi
	check_gpl "$@"
}

if [ "${1:-}" = -f ]; then
	if [ $# -lt 2 ] || [ $# -gt 3 ]; then
		echo "usage: check-license.sh -f fork [base]" >&2
		exit 2
	fi
	fork=$(cd "$2" && pwd)
	base=${3:-upstream}
	list=$(git -C "$fork" diff --name-status --no-renames "$base")
	ours=0
	imported=0
	changed=0
	while read -r st f; do
		[ -n "$f" ] || continue
		case $st in
		A)
			case $f in
			libc/upstream-*/lib/*)
				check_imported "$fork/$f" "$f"
				imported=$((imported + 1)) ;;
			*)
				if is_source "$f"; then
					check_ours "$fork/$f" "$f"
				else
					check_gpl "$fork/$f" "$f"
				fi
				ours=$((ours + 1)) ;;
			esac ;;
		M)
			check_gpl "$fork/$f" "$f"
			changed=$((changed + 1)) ;;
		esac
	done <<-END
	$list
	END
	if [ "$status" -eq 0 ]; then
		echo "license check passed ($ours new, $imported imported and" \
		    "$changed changed files against $base)"
	fi
	exit "$status"
fi

cd "$(dirname "$0")/.."
[ $# -gt 0 ] || set -- kmod tests tools guest

files=$(find "$@" -type f \( -name '*.c' -o -name '*.h' -o -name '*.cpp' \
    -o -name '*.S' -o -name '*.inc' -o -name '*.sh' -o -name '*.awk' \
    -o -name '*.py' -o -name '*.rs' -o -name '*.[1-9]' -o -name 'Makefile' \
    -o -name 'CMakeLists.txt' -o -name '*.cmake' -o -name '*.excluded' \
    -o -name 'SYSCALLS.FREEBSD.TXT' \) 2>/dev/null | sort)

for f in $files; do
	[ "$f" = "$self" ] && continue	# contains the patterns it searches for
	check_ours "$f"
done

if [ "$status" -eq 0 ]; then
	echo "license check passed ($(echo "$files" | grep -c . || true) files)"
fi
exit "$status"
