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

set -eu

cd "$(dirname "$0")/.."
[ $# -gt 0 ] || set -- kmod tests tools guest

status=0
files=$(find "$@" -type f \( -name '*.c' -o -name '*.h' -o -name '*.cpp' \
    -o -name '*.S' -o -name '*.inc' -o -name '*.sh' -o -name '*.py' \
    -o -name '*.rs' -o -name '*.[1-9]' -o -name 'Makefile' \
    -o -name 'CMakeLists.txt' -o -name '*.cmake' -o -name '*.excluded' \
    -o -name 'SYSCALLS.FREEBSD.TXT' \) 2>/dev/null | sort)

self="tools/check-license.sh"
for f in $files; do
	[ "$f" = "$self" ] && continue	# contains the patterns it searches for
	if ! head -n 12 "$f" | grep -q 'SPDX-License-Identifier: BSD-2-Clause'; then
		echo "missing BSD-2-Clause SPDX header: $f"
		status=1
	fi
	if ! head -n 40 "$f" |
	    grep -q 'Redistribution and use in source and binary forms'; then
		echo "missing BSD-2-Clause license text: $f"
		status=1
	fi
	if grep -q -F '<copyright'' holder>' "$f"; then
		echo "placeholder copyright holder: $f"
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
