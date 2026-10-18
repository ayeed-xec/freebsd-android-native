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
# rev.sh -- print the pinned revision of AOSP projects from a repo manifest
# (plan §9.1).  It prints one line for each project, in argument order.
#
#   sh aosp/manifest/rev.sh <manifest.xml> [-v] <project>...
#   sh aosp/manifest/rev.sh <manifest.xml> -a
#
# A project is a googlesource name such as platform/bionic.  -v prints
# "<revision> <path> <name>".  -a prints that line for each project of the
# manifest, in manifest order.  A project without a revision attribute
# gets the revision of <default>.  Exit 1 if a project is not in the
# manifest.
#
# The manifest is a trusted input: check its MD5 against plan §9.1 first
# (aosp/fetch.sh does this).  The reader takes the XML that repo writes:
# elements, comments and quoted attributes.  It refuses an attribute value
# with an entity reference.

usage()
{
	echo "usage: rev.sh <manifest.xml> [-v] <project>..." >&2
	echo "       rev.sh <manifest.xml> -a" >&2
	exit 2
}

set -f
all=0
verbose=0
manifest=
names=
for a; do
	case $a in
	-a)	all=1 ;;
	-v)	verbose=1 ;;
	*)	if [ -z "$manifest" ]; then
			manifest=$a
		else
			names="$names $a"
		fi
		;;
	esac
done
[ -n "$manifest" ] || usage
if [ "$all" -eq 1 ]; then
	[ -z "$names" ] || usage
else
	[ -n "$names" ] || usage
fi
if [ ! -r "$manifest" ]; then
	echo "rev.sh: $manifest: cannot read" >&2
	exit 1
fi

# With RS=">", each record is the text up to the end of one tag.
# shellcheck disable=SC2086
exec awk -v all="$all" -v verbose="$verbose" -v manifest="$manifest" '
function fail(msg) {
	print "rev.sh: " manifest ": " msg > "/dev/stderr"
	bad = 1
	exit 1
}

# Set found and return the value of attribute key of tag t.
function attr(t, key,    v) {
	found = 0
	if (!match(t, "[[:space:]]" key "[[:space:]]*=[[:space:]]*" \
	    "(\"[^\"]*\"|\047[^\047]*\047)"))
		return ("")
	v = substr(t, RSTART, RLENGTH)
	sub(/^[^=]*=[[:space:]]*/, "", v)
	v = substr(v, 2, length(v) - 2)
	if (index(v, "&") != 0)
		fail("entity in attribute " key)
	found = 1
	return (v)
}

BEGIN {
	RS = ">"
	for (i = 2; i < ARGC; i++) {
		want[++nwant] = ARGV[i]
		ARGV[i] = ""
	}
}

{
	t = $0
	if (incomment) {
		if (t ~ /--$/)
			incomment = 0
		next
	}
	if ((i = index(t, "<!--")) != 0) {
		t = substr(t, i + 4)
		if (length(t) < 2 || t !~ /--$/)
			incomment = 1
		next
	}
	if (!seen_default && t ~ /<default([[:space:]]|\/|$)/) {
		seen_default = 1
		drev = attr(t, "revision")
		has_drev = found
		next
	}
	if (t !~ /<project([[:space:]]|\/|$)/)
		next
	name = attr(t, "name")
	if (!found)
		fail("project without name or revision")
	rev = attr(t, "revision")
	if (!found) {
		rev = drev
		found = has_drev
	}
	if (!found)
		fail("project without name or revision")
	path = attr(t, "path")
	if (!found)
		path = name
	if (!(name in known))
		order[++nproj] = name
	known[name] = 1
	prj_path[name] = path
	prj_rev[name] = rev
}

END {
	if (bad)
		exit 1
	if (all) {
		for (i = 1; i <= nproj; i++)
			print prj_rev[order[i]], prj_path[order[i]], order[i]
		exit 0
	}
	status = 0
	for (i = 1; i <= nwant; i++) {
		n = want[i]
		if (!(n in known)) {
			print "rev.sh: " n ": not in " manifest > "/dev/stderr"
			status = 1
			continue
		}
		if (verbose)
			print prj_rev[n], prj_path[n], n
		else
			print prj_rev[n]
	}
	exit status
}' "$manifest" $names
