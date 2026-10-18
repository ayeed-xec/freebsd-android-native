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
# fetch.sh -- fetch AOSP projects at the revisions of the pinned manifest
# (plan §9.1): blobless, depth 1, sparse, fetch by SHA.
#
#   sh aosp/fetch.sh [--week N] [--dest DIR] [--dry-run] [ROW...]
#   sh aosp/fetch.sh --project NAME[:DIR,...] [--project ...]
#   sh aosp/fetch.sh --list
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
# --manifest and --md5 (or "none") select another manifest.
#
# Exit 0 if every HEAD equals its revision, else 1.  A row over its budget is
# reported but is not an error.  Exit 2 for a usage error.

set -f			# the sparse patterns contain "*"
set -u

here=$(cd "$(dirname "$0")" && pwd -P)
manifest=$here/manifest/manifest_16373615.xml
md5=b3a6e0f1bc95a05af277a13bf5dd2b8c
remote=https://android.googlesource.com/
fallback_ref=refs/tags/android-17.0.0_r1
GIT_TERMINAL_PROMPT=0
export GIT_TERMINAL_PROMPT

# Plan §9.1: row, week, budget in MB and project.  A "+" line gives the
# directories of a sparse fetch, a "-" line the directories under them to
# leave out.  A project without "+" lines is fetched whole.
table()
{
	awk '
	function flush() {
		if (p != "")
			print p, (dirs == "" ? "-" : dirs), (excl == "" ? "-" : excl)
		p = dirs = excl = ""
	}
	/^#/ || NF == 0 { next }
	$1 == "+" || $1 == "-" {
		for (i = 2; i <= NF; i++) {
			if ($1 == "+")
				dirs = dirs (dirs == "" ? "" : ",") $i
			else
				excl = excl (excl == "" ? "" : ",") $i
		}
		next
	}
	{ flush(); p = $1 " " $2 " " $3 " " $4 }
	END { flush() }' <<'EOF'
1 1 10 platform/system/libbase
2 1 20 platform/system/logging
	+ liblog logd logcat logwrapper
3 1 60 platform/system/core
	+ libcutils libutils include init rootdir libprocessgroup
	+ property_service toolbox libsystem libsysutils libpackagelistparser
4 1 10 platform/system/libziparchive
5 1 5 platform/system/libprocinfo
6 1 15 platform/external/fmtlib
	+ include src
7 1 80 platform/frameworks/native
	+ libs/binder cmds/servicemanager cmds/service include
8 1 20 platform/system/tools/aidl
# Rev 2: the whole runtime, minus the malloc traces (about 95 MB).
9 1 100 platform/bionic
	+ libc libm libdl linker tests docs
	- libc/memory/replay/traces
10 1 50 platform/libcore
	+ luni/src/main/native ojluni/src/main/native
	+ luni/src/main/java/android/system
11 1 10 platform/libnativehelper
12 2 20 platform/build/blueprint
13 2 70 platform/art
	+ build libartbase libdexfile libprofile libelffile libartpalette
	+ runtime sigchainlib dalvikvm libnativebridge libnativeloader
	+ dexdump cmdline tools
14 2 150 platform/external/icu
	+ icu4c/source/common icu4c/source/i18n icu4c/source/stubdata
	+ libicu libandroidicu android_icu4c
15 2 20 platform/external/vixl
	+ src
16 2 40 platform/external/zlib
16 2 40 platform/external/lz4
16 2 40 platform/external/lzma
# Upstream, not pinned by the manifest: the tool reports it as manual.
17 2 5 github.com/google/cpu_features
18 2 150 platform/frameworks/base
	+ core/jni services/core/jni cmds/app_process core/java/android/os
# compiler-rt builtins and libunwind are not in the manifest (plan (u)).
19 2 60 platform/external/libcxx
	+ src include
19 2 60 platform/external/libcxxabi
	+ src include
19 2 60 platform/external/jemalloc_new
EOF
}

# usage [STATUS]: print the usage; to standard error unless STATUS is 0.
usage()
{
	_u="usage: fetch.sh [--week N] [--dest DIR] [--manifest FILE] \
[--md5 SUM|none]
                [--project NAME[:DIR,...]] [--dry-run] [--list] [ROW...]"
	if [ "${1:-2}" -eq 0 ]; then
		printf '%s\n' "$_u"
	else
		printf '%s\n' "$_u" >&2
	fi
	exit "${1:-2}"
}

# Print a path in the form that Python's pathlib gives: no empty or "."
# components and no slash at the end.
normpath()
{
	printf '%s\n' "$1" | awk -F/ '{
		p = ""
		for (i = 1; i <= NF; i++)
			if ($i != "" && $i != ".")
				p = p (p == "" ? "" : "/") $i
		if (substr($0, 1, 1) == "/")
			p = "/" p
		print (p == "" ? "." : p)
	}'
}

# Print kilobytes as megabytes with one decimal.
mb()
{
	awk -v k="$1" 'BEGIN { printf("%.1f", k / 1024) }'
}

# Print the size of a path in kilobytes, or 0.
du_kb()
{
	_out=$(du "$@" 2>/dev/null) || _out=
	set -- $_out
	echo "${1:-0}"
}

# Print each word of the input on its own line.
words()
{
	awk '{ for (i = 1; i <= NF; i++) print $i }'
}

# Print the items of a comma list on their own lines.
items()
{
	printf '%s\n' "$1" | tr ',' '\n'
}

# git_run DIR ARGS...: print the git command in dry-run mode, else run it.
# On failure, set git_err to the error of git and fp_err to the message.
git_run()
{
	_gd=$1
	shift
	if [ "$dry_run" -eq 1 ]; then
		printf '  $ git -C %s %s\n' "$_gd" "$*"
		return 0
	fi
	if ! git_err=$(git -C "$_gd" "$@" 2>&1 >/dev/null </dev/null); then
		fp_err="git -C $_gd $*: $git_err"
		return 1
	fi
}

# git_out DIR ARGS...: run a git command that changes nothing.
git_out()
{
	_gd=$1
	shift
	git -C "$_gd" "$@" 2>/dev/null </dev/null
}

# The non-cone sparse patterns: the top-level files, the directories, then
# the directories to leave out.
patterns()
{
	printf '%s\n' '/*' '!/*/'
	items "$1" | sed 's|.*|/&/|'
	items "$2" | sed 's|.*|!/&/|'
}

# Set sp_enabled, sp_cone and sp_pats from the sparse state of a repository.
sparse_state()
{
	sp_enabled=0
	sp_cone=0
	sp_pats=
	[ "$(git_out "$1" config --bool core.sparseCheckout)" = true ] ||
	    return 0
	sp_enabled=1
	[ "$(git_out "$1" config --bool core.sparseCheckoutCone)" = true ] &&
	    sp_cone=1
	_f=$(git_out "$1" rev-parse --git-path info/sparse-checkout) || _f=
	case $_f in
	/*)	;;
	*)	_f=$1/$_f ;;
	esac
	if [ -f "$_f" ]; then
		sp_pats=$(words < "$_f")
	fi
}

# same_sparse DIR DIRS EXCLUDE: true if the repository has the wanted
# sparse set.
same_sparse()
{
	sparse_state "$1"
	if [ "$2" = - ]; then
		[ "$sp_enabled" -eq 0 ]
		return
	fi
	[ "$sp_enabled" -eq 1 ] || return 1
	if [ "$3" != - ]; then
		[ "$sp_cone" -eq 0 ] && [ "$sp_pats" = "$(patterns "$2" "$3")" ]
		return
	fi
	[ "$sp_cone" -eq 1 ] || return 1
	[ "$(git_out "$1" sparse-checkout list | words | LC_ALL=C sort)" = \
	    "$(items "$2" | LC_ALL=C sort)" ]
}

# fetch_project NAME PATH DIRS EXCLUDE REV: fetch one project.  Set
# fp_status and fp_head, or fp_err on failure.
fetch_project()
{
	_d=$dest/$2
	if [ -d "$_d/.git" ] &&
	    [ "$(git_out "$_d" rev-parse HEAD)" = "$5" ] &&
	    same_sparse "$_d" "$3" "$4"; then
		fp_status=present
		fp_head=$5
		return 0
	fi
	if [ "$dry_run" -eq 0 ]; then
		fp_err=$(mkdir -p "$_d" 2>&1) || return 1
	fi
	git_run "$_d" init -q || return 1
	if git_out "$_d" remote get-url origin >/dev/null; then
		git_run "$_d" remote set-url origin "$remote$1" || return 1
	else
		git_run "$_d" remote add origin "$remote$1" || return 1
	fi
	if [ "$3" = - ]; then
		sparse_state "$_d"
		if [ "$sp_enabled" -eq 1 ]; then
			git_run "$_d" sparse-checkout disable || return 1
		fi
	elif [ "$4" != - ]; then
		git_run "$_d" sparse-checkout set --no-cone \
		    $(patterns "$3" "$4") || return 1
	else
		git_run "$_d" sparse-checkout set --cone $(items "$3") ||
		    return 1
	fi
	fp_status=sha
	if ! git_run "$_d" fetch -q --depth=1 --filter=blob:none origin "$5"
	then
		echo "  $1: fetch by SHA refused: $git_err" >&2
		git_run "$_d" fetch -q --depth=1 --filter=blob:none origin \
		    "$fallback_ref" || return 1
		fp_status=tag
	fi
	git_run "$_d" -c advice.detachedHead=false checkout -q FETCH_HEAD ||
	    return 1
	if [ "$dry_run" -eq 1 ]; then
		fp_status=dry-run
		fp_head=$5
		return 0
	fi
	fp_head=$(git_out "$_d" rev-parse HEAD) || fp_head=
	return 0
}

week=1
dest=${AOSP_SRC:-$HOME/aosp}
dry_run=0
list=0
rows=
specs=
while [ $# -gt 0 ]; do
	case $1 in
	--week=*)	week=${1#*=} ;;
	--dest=*)	dest=${1#*=} ;;
	--manifest=*)	manifest=${1#*=} ;;
	--md5=*)	md5=${1#*=} ;;
	--project=*)	specs="$specs ${1#*=}" ;;
	--week|--dest|--manifest|--md5|--project)
		[ $# -ge 2 ] || usage
		case $1 in
		--week)		week=$2 ;;
		--dest)		dest=$2 ;;
		--manifest)	manifest=$2 ;;
		--md5)		md5=$2 ;;
		--project)	specs="$specs $2" ;;
		esac
		shift
		;;
	--dry-run)	dry_run=1 ;;
	--list)		list=1 ;;
	-h|--help)	usage 0 ;;
	--)		shift
			rows="$rows $*"
			break
			;;
	-*)		usage ;;
	*)		rows="$rows $1" ;;
	esac
	shift
done
for r in $rows $week; do
	case $r in
	''|*[!0-9]*)	usage ;;
	esac
done
dest=$(normpath "$dest")

if [ "$md5" != none ] &&
    [ "$(md5 -q "$manifest" 2>/dev/null)" != "$md5" ]; then
	echo "fetch.sh: $manifest: MD5 is not $md5" >&2
	exit 1
fi
pins=$(sh "$here/manifest/rev.sh" "$manifest" -a) || exit 1

# The selected lines: row, week, budget, project, directories, exclude.
if [ -n "$rows" ]; then
	want=$(for r in $rows; do expr "$r" + 0; done)
	sel=$(table | awk -v want=" $(echo $want) " \
	    'index(want, " " $1 " ") != 0')
	nsel=$(printf '%s\n' "$sel" | awk 'NF { print $1 }' | sort -u | wc -l)
	nwant=$(printf '%s\n' $want | sort -u | wc -l)
	if [ $((nsel)) -ne $((nwant)) ]; then
		echo "fetch.sh: a ROW is not in 1-19" >&2
		exit 2
	fi
elif [ -z "$specs" ]; then
	sel=$(table | awk -v w="$week" '$2 == w')
else
	sel=
fi
for s in $specs; do
	case $s in
	*:*)	d=${s#*:} ;;
	*)	d= ;;
	esac
	sel="$sel
+ 0 - ${s%%:*} ${d:--} -"
done

failed=0
total_kb=0
budget_mb=0
if [ "$list" -eq 1 ]; then
	printf '%2s %-34s %-12s path\n' '#' project revision
else
	printf '%2s %-34s %-12s %-8s %-4s %6s %6s\n' '#' project revision \
	    status HEAD MB budget
fi

# end_row NUM BUDGET ROW_KB: the totals and the budget check of a row.
end_row()
{
	[ "$list" -eq 0 ] && [ "$dry_run" -eq 0 ] || return 0
	total_kb=$((total_kb + $3))
	[ "$2" = - ] && return 0
	budget_mb=$((budget_mb + $2))
	if [ "$3" -gt $(($2 * 1024)) ]; then
		printf '%2s over budget: %s MB > %s MB\n' "$1" "$(mb "$3")" "$2"
	fi
}

prev=
prev_budget=
row_kb=0
while read -r num week_ budget name dirs exclude; do
	[ -n "$num" ] || continue
	if [ -n "$prev" ] && { [ "$num" != "$prev" ] || [ "$num" = + ]; }; then
		end_row "$prev" "$prev_budget" "$row_kb"
		row_kb=0
	fi
	prev=$num
	prev_budget=$budget
	pin=$(printf '%s\n' "$pins" | awk -v n="$name" '$3 == n { r = $1 " " $2 }
	    END { if (r != "") print r }')
	if [ -z "$pin" ]; then
		printf '%2s %-34s %-12s %-8s %-4s %6s %6s  not in the manifest\n' \
		    "$num" "$name" - manual - - -
		continue
	fi
	sha=${pin%% *}
	path=${pin#* }
	sha12=$(printf '%.12s' "$sha")
	if [ "$list" -eq 1 ]; then
		printf '%2s %-34s %-12s %s\n' "$num" "$name" "$sha12" "$path"
		continue
	fi
	case $sha in
	*[!0-9a-f]*)	ok=0 ;;
	*)		ok=1 ;;
	esac
	if [ "$ok" -eq 0 ] || [ ${#sha} -ne 40 ]; then
		printf '%2s %-34s %-12s not a SHA-1\n' "$num" "$name" "$sha" >&2
		failed=1
		continue
	fi
	if ! fetch_project "$name" "$path" "$dirs" "$exclude" "$sha"; then
		printf '%2s %-34s %-12s error: %s\n' "$num" "$name" "$sha12" \
		    "$fp_err" >&2
		failed=1
		continue
	fi
	if [ "$dry_run" -eq 1 ]; then
		mark=-
		kb=0
	elif [ "$fp_head" = "$sha" ]; then
		mark=ok
		kb=$(du_kb -sk "$dest/$path")
	else
		mark=BAD
		failed=1
		kb=$(du_kb -sk "$dest/$path")
	fi
	row_kb=$((row_kb + kb))
	printf '%2s %-34s %-12s %-8s %-4s %6s %6s\n' "$num" "$name" "$sha12" \
	    "$fp_status" "$mark" "$(mb "$kb")" "$budget"
done <<EOF
$sel
EOF
[ -n "$prev" ] && end_row "$prev" "$prev_budget" "$row_kb"
if [ "$list" -eq 0 ] && [ "$dry_run" -eq 0 ]; then
	printf 'total %s MB for the rows, budget %s MB; du -sk %s: %s MB\n' \
	    "$(mb "$total_kb")" "$budget_mb" "$dest" \
	    "$(mb "$(du_kb -H -sk "$dest")")"
fi
exit "$failed"
