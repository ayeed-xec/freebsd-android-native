/*
 * Copyright (c) 2026 Ayeed Shaikh <Ayeed.AI10@race.reva.edu.in>
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/*
 * M1 test (L1): signals on FreeBSD.  It checks sigaction(2) with
 * SA_SIGINFO, sigqueue(2) with a value, a real-time signal above 64 (the
 * 128-bit sigset_t), raise(3) and pthread_kill(3) on thr_kill2(2),
 * sigprocmask(2) with sigpending(2), and sigtimedwait(2) with a timeout
 * (the errno translation).  It prints "signals ok" and exits 0 on success.
 */

#include <sys/types.h>

#include <err.h>
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t	got_code;
static volatile sig_atomic_t	got_signo;
static volatile sig_atomic_t	got_value;

static void
handler(int signo, siginfo_t *info, void *context)
{
	(void)context;
	got_signo = signo;
	got_code = info->si_code;
	got_value = info->si_value.sival_int;
}

static void
set_handler(int signo)
{
	struct sigaction sa;

	memset(&sa, 0, sizeof(sa));
	sa.sa_sigaction = handler;
	sa.sa_flags = SA_SIGINFO;
	sigemptyset(&sa.sa_mask);
	if (sigaction(signo, &sa, NULL) != 0)
		err(1, "sigaction %d", signo);
}

static void
check_queue(int signo, int value)
{
	union sigval sv;

	got_signo = 0;
	sv.sival_int = value;
	if (sigqueue(getpid(), signo, sv) != 0)
		err(1, "sigqueue %d", signo);
	if (got_signo != signo || got_code != SI_QUEUE || got_value != value)
		errx(1, "sigqueue %d: signo %d code %d value %d", signo,
		    (int)got_signo, (int)got_code, (int)got_value);
}

int
main(void)
{
	struct timespec timeout;
	sigset_t pending, set;
	siginfo_t info;
	int rt, signo;

	rt = SIGRTMIN + 1;
	if (rt <= 64 || rt > SIGRTMAX)
		errx(1, "SIGRTMIN %d, SIGRTMAX %d", SIGRTMIN, SIGRTMAX);
	set_handler(SIGUSR1);
	set_handler(rt);
	check_queue(SIGUSR1, 1234);
	check_queue(rt, 5678);

	got_signo = 0;
	if (raise(SIGUSR1) != 0 || got_signo != SIGUSR1)
		errx(1, "raise");
	got_signo = 0;
	if (pthread_kill(pthread_self(), SIGUSR1) != 0 || got_signo != SIGUSR1)
		errx(1, "pthread_kill");

	sigemptyset(&set);
	sigaddset(&set, SIGUSR2);
	sigaddset(&set, rt);
	if (sigprocmask(SIG_BLOCK, &set, NULL) != 0)
		err(1, "sigprocmask");
	if (kill(getpid(), SIGUSR2) != 0)
		err(1, "kill");
	if (sigpending(&pending) != 0 || !sigismember(&pending, SIGUSR2) ||
	    sigismember(&pending, rt))
		errx(1, "sigpending");
	timeout.tv_sec = 1;
	timeout.tv_nsec = 0;
	signo = sigtimedwait(&set, &info, &timeout);
	if (signo != SIGUSR2 || info.si_signo != SIGUSR2 ||
	    info.si_code != SI_USER || info.si_pid != getpid())
		errx(1, "sigtimedwait: %d", signo);
	timeout.tv_sec = 0;
	timeout.tv_nsec = 1000000;
	if (sigtimedwait(&set, &info, &timeout) != -1 || errno != EAGAIN)
		errx(1, "sigtimedwait timeout: errno %d", errno);

	printf("signals ok\n");
	return (0);
}
