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
# usage: logcat-two-processes.sh jail.conf
#
# In the bionic_tests jail of jail.conf, where svcstart starts logd, two
# logwrapper processes each write one line to the log through logd, and
# "logcat -d" reads the log back.  The check passes when logcat shows both
# lines, from two different pids.  As run-gtest-suite.sh does, the script
# makes the jail with mdo(1), runs the programs as the calling user, as
# under "adb shell", and removes the jail at the end.

set -u

conf=$1
if [ -z "${GTEST_JAIL_LOCKED:-}" ]; then
	GTEST_JAIL_LOCKED=1 exec lockf -k /tmp/bionic_tests.lock sh "$0" "$@"
fi
mdo jail -q -f "$conf" -r bionic_tests 2>/dev/null
mdo jail -q -f "$conf" -c bionic_tests || exit 1
trap 'mdo jail -q -f "$conf" -r bionic_tests' EXIT
trap 'exit 1' HUP INT TERM

out=$(mdo jexec -u "$(id -un)" -d /tmp bionic_tests /system/bin/sh -c '
	/system/bin/logwrapper /system/bin/sh -c "echo logd check: first"
	/system/bin/logwrapper /system/bin/sh -c "echo logd check: second"
	/system/bin/logcat -d -v threadtime -v uid' 2>/dev/null)
echo "$out"
# A line is "date time uid pid tid priority tag: message".  logcat gives
# the Android name of the uid: the uid of the calling user, in both lines.
echo "$out" | awk -v uid="$(id -u)" '
	/logd check: first$/ { first = $4; u1 = $3 }
	/logd check: second$/ { second = $4; u2 = $3 }
	END {
		if (first == "" || second == "" || first == second ||
		    u1 != u2)
			exit 1
		print "logcat: two processes, pids " first " and " second \
		    ", uid " u1 " (" uid ")"
	}'
