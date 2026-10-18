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
# usage: run-in-jail.sh jail.conf command [arg ...]
#
# Run one command in the bionic_tests jail of jail.conf as the calling user
# and exit with its status.  The jail is made with mdo(1) and removed at the
# end, as in run-gtest-suite.sh.  When mdo cannot give root there is no jail
# and no property service, so exit with 77, which ctest reports as skipped.

set -u

conf=$1
shift
if ! mdo true 2>/dev/null; then
	echo "mdo cannot give root, so there is no jail"
	exit 77
fi
# Other build trees in the VM use the same jail and Android root.
if [ -z "${JAIL_LOCKED:-}" ]; then
	JAIL_LOCKED=1 exec lockf -k /tmp/bionic_tests.lock sh "$0" "$conf" "$@"
fi
# With the lock held, a jail that exists is left from a killed run.
mdo jail -q -f "$conf" -r bionic_tests 2>/dev/null
mdo jail -q -f "$conf" -c bionic_tests || exit 1
trap 'mdo jail -q -f "$conf" -r bionic_tests' EXIT
trap 'exit 1' HUP INT TERM
mdo jexec -u "$(id -un)" -d /tmp bionic_tests "$@"
rc=$?
exit $rc
