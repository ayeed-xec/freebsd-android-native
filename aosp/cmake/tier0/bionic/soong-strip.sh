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
# usage: soong-strip.sh [-k] in out
#
# Install a device program or shared library stripped, as Soong's strip
# rule does in a debuggable build.  By default out keeps the mini debug
# information: the symbols of the functions that are not dynamic and
# .debug_frame, compressed with xz in .gnu_debugdata.  With -k (strip:
# keep_symbols) out keeps its symbol table and gets a .gnu_debuglink to in.
# The tools come from LLVM_STRIP, LLVM_OBJCOPY, LLVM_NM and XZ.

set -eu

usage()
{
	echo "usage: soong-strip.sh [-k] in out" >&2
	exit 2
}

keep=
while getopts k opt; do
	case $opt in
	k)
		keep=1
		;;
	*)
		usage
		;;
	esac
done
shift $((OPTIND - 1))
[ $# -eq 2 ] || usage
in=$1
out=$2
tmp=$out.tmp

rm -f "$tmp"
if [ -n "$keep" ]; then
	"$LLVM_OBJCOPY" -w --remove-section='.debug_*' "$in" "$tmp"
	"$LLVM_OBJCOPY" --add-gnu-debuglink="$in" "$tmp"
else
	"$LLVM_STRIP" --strip-all --keep-section=.ARM.attributes \
	    --remove-section=.comment "$in" -o "$tmp"
	d=$(mktemp -d "${TMPDIR:-/tmp}/soong-strip.XXXXXX")
	trap 'rm -rf "$d"' EXIT
	"$LLVM_OBJCOPY" --only-keep-debug "$in" "$d/debug"
	"$LLVM_NM" -D --format=posix --defined-only "$in" 2>/dev/null |
	    awk '{ print $1 }' | sort > "$d/dynsyms"
	"$LLVM_NM" --format=posix --defined-only "$in" |
	    awk '$2 == "T" || $2 == "t" || $2 == "D" { print $1 }' |
	    sort > "$d/funcsyms"
	comm -13 "$d/dynsyms" "$d/funcsyms" > "$d/keep"
	# The list must not be empty.
	echo >> "$d/keep"
	"$LLVM_OBJCOPY" -S --keep-section .debug_frame \
	    --keep-symbols="$d/keep" "$d/debug" "$d/mini"
	"$XZ" --block-size=64k --threads=0 "$d/mini"
	"$LLVM_OBJCOPY" --add-section .gnu_debugdata="$d/mini.xz" "$tmp"
fi
mv -f "$tmp" "$out"
