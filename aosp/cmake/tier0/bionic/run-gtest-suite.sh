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
# usage: run-gtest-suite.sh [-j jail.conf [-d path] [-r]] [-s] excluded
#            command [arg ...]
#
# Run each test of a gtest suite in its own process, 6 at a time, which is
# what the isolated runner of gtest_extras would do.  With -s the tests run
# one at a time, for a suite that Android runs in one process: its tests
# can share state, such as a system property.  The isolated runner lists the
# tests through popen(), which runs "sh -c -- cmd", and FreeBSD's /bin/sh
# takes the "--" as the command.  Android's own shell, /system/bin/sh in the
# jail, does not have this problem.  The tests named in the excluded file
# are left out.
#
# With -j the command is "linker64 program" or a static program.  The
# program and each path of -d (a file or a directory; -d can repeat) are
# copied to /data/local/tmp/<program> in the bionic_tests jail of
# jail.conf, as "adb push" does.  The program runs from there, a dynamic
# one through its PT_INTERP, and each test is a child of the jail's sh, as
# under "adb shell".  The jail is made with mdo(1) and removed at the end.
# The tests run as the calling user, who owns /data/local/tmp as the shell
# user does on a device, or with -r as root, as Android runs a test module
# that has require_root.  When mdo cannot give root, the command runs as it
# is, and the env:linker64-run tests are left out as well.  The tests that
# need the jail's helper programs, its property service or its Android root
# then fail.

set -u

conf=
data=
opts=
user=$(id -un)
jobs=6
while getopts d:j:rs opt; do
	case $opt in
	d)	data="$data $OPTARG"
		opts="$opts -d $OPTARG" ;;
	j)	conf=$OPTARG ;;
	r)	user=root
		opts="$opts -r" ;;
	s)	jobs=1
		opts="$opts -s" ;;
	*)	echo "usage: run-gtest-suite.sh [-j jail.conf [-d path] [-r]]" \
		    "[-s] excluded command [arg ...]" >&2
		exit 2 ;;
	esac
done
shift $((OPTIND - 1))
excluded=$1
shift

keep=
if [ -n "$conf" ] && mdo true 2>/dev/null; then
	# Other build trees in the VM use the same jail and Android root.
	if [ -z "${GTEST_JAIL_LOCKED:-}" ]; then
		GTEST_JAIL_LOCKED=1 exec lockf -k /tmp/bionic_tests.lock \
		    sh "$0" -j "$conf" $opts "$excluded" "$@"
	fi
	for prog; do :; done
	# With the lock held, a jail that exists is left from a killed run.
	mdo jail -q -f "$conf" -r bionic_tests 2>/dev/null
	mdo jail -q -f "$conf" -c bionic_tests || exit 1
	trap 'mdo jail -q -f "$conf" -r bionic_tests' EXIT
	trap 'exit 1' HUP INT TERM
	jail_root=$(jls -j bionic_tests path) || exit 1
	mdo chown "$(id -u):$(id -g)" "$jail_root/data/local/tmp" || exit 1
	# /data keeps the copy of the last run.
	dir=/data/local/tmp/${prog##*/}
	rm -rf "$jail_root$dir"
	mkdir "$jail_root$dir" &&
	    cp -Rp "$prog" $data "$jail_root$dir" || exit 1
	unset LD_LIBRARY_PATH
	keep=env:linker64-run
	# jexec -u sets the PATH of the login class; the tests get ours.
	set -- mdo jexec -u "$user" -d /tmp bionic_tests /bin/sh -c \
	    'PATH=$1; export PATH; shift; "$0" "$@"; exit $?' \
	    "$dir/${prog##*/}" "$PATH"
fi

tmp=$(mktemp -d)
awk -v keep="$keep" '!/^#/ && NF && $2 != keep { print $1 }' "$excluded" \
    > "$tmp/excluded"
"$@" --no_isolate --gtest_list_tests |
    awk '/^[^ ]/ { s = $1 } /^  / { print s $1 }' |
    grep -v DISABLED_ > "$tmp/built"
grep -vxFf "$tmp/excluded" "$tmp/built" > "$tmp/tests"
# The name of a value-parameterized test has "/" in it, so its log goes in a
# subdirectory.
xargs -P "$jobs" -I % sh -c 't=$0 tmp=$1; shift; mkdir -p "$(dirname "$tmp/$t")"
    cd /tmp && TMPDIR=/tmp \
    timeout 120 "$@" --no_isolate "--gtest_filter=$t" > "$tmp/$t.log" 2>&1 ||
    echo "$t"' % "$tmp" "$@" < "$tmp/tests" > "$tmp/failed"
echo "$(wc -l < "$tmp/tests") tests run, $(wc -l < "$tmp/failed") failed"
for t in $(cat "$tmp/failed"); do
	echo "=== $t"
	tail -20 "$tmp/$t.log"
done
# One line for each built test, for tools/gates/g1.sh: PASS, SKIP (the
# test called GTEST_SKIP()), FAIL or EXCLUDED.
find "$tmp" -name '*.log' -exec grep -l '^\[  SKIPPED \]' {} + > "$tmp/skipped"
echo "results:"
awk -v dir="$tmp/" '
	FILENAME == ARGV[1] { st[$0] = "EXCLUDED"; next }
	FILENAME == ARGV[2] { st[$0] = "FAIL"; next }
	FILENAME == ARGV[3] {
		t = substr($0, length(dir) + 1)
		sub(/\.log$/, "", t)
		if (!(t in st))
			st[t] = "SKIP"
		next
	}
	{ print ($0 in st ? st[$0] : "PASS"), $0 }
' "$tmp/excluded" "$tmp/failed" "$tmp/skipped" "$tmp/built"
test ! -s "$tmp/failed"
rc=$?
rm -rf "$tmp"
exit $rc
