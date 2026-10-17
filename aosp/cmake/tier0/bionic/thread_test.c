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
 * M1 test (A2): threads on thr_new(2) and thr_exit(2), and mutexes on
 * _umtx_op(2).  It checks pthread_create() and pthread_join() with return
 * values, pthread_exit(), a detached thread, gettid(), normal, recursive and
 * errorcheck mutexes under contention, a condition variable and
 * pthread_once().  It prints "threads ok" and exits 0 on success.
 */

#include <sys/types.h>

#include <err.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

#define	NLOOPS		20000
#define	NTHREADS	8

static pthread_cond_t	 done_cond = PTHREAD_COND_INITIALIZER;
static pthread_mutex_t	 done_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t	 once = PTHREAD_ONCE_INIT;
static pthread_mutex_t	*counter_lock;
static long		 counter;
static int		 detached_done;
static int		 once_count;

static void
once_init(void)
{
	once_count++;
}

static void *
add_loop(void *arg)
{
	int i;

	(void)arg;
	pthread_once(&once, once_init);
	for (i = 0; i < NLOOPS; i++) {
		if (pthread_mutex_lock(counter_lock) != 0)
			errx(1, "pthread_mutex_lock");
		counter++;
		if (pthread_mutex_unlock(counter_lock) != 0)
			errx(1, "pthread_mutex_unlock");
	}
	return ((void *)(intptr_t)gettid());
}

static void *
exit_with_value(void *arg)
{
	pthread_exit(arg);
}

static void *
detached_main(void *arg)
{
	(void)arg;
	pthread_mutex_lock(&done_lock);
	detached_done = 1;
	pthread_cond_signal(&done_cond);
	pthread_mutex_unlock(&done_lock);
	return (NULL);
}

static void
contend(int type)
{
	pthread_t threads[NTHREADS];
	pthread_mutexattr_t attr;
	pthread_mutex_t lock;
	void *ret;
	int i;

	pthread_mutexattr_init(&attr);
	pthread_mutexattr_settype(&attr, type);
	pthread_mutex_init(&lock, &attr);
	pthread_mutexattr_destroy(&attr);
	counter_lock = &lock;
	counter = 0;
	for (i = 0; i < NTHREADS; i++)
		if (pthread_create(&threads[i], NULL, add_loop, NULL) != 0)
			errx(1, "pthread_create");
	for (i = 0; i < NTHREADS; i++) {
		if (pthread_join(threads[i], &ret) != 0)
			errx(1, "pthread_join");
		if ((intptr_t)ret <= 0 || (intptr_t)ret == gettid())
			errx(1, "thread %d returned tid %ld", i, (long)(intptr_t)ret);
	}
	if (counter != (long)NTHREADS * NLOOPS)
		errx(1, "mutex type %d: counter %ld", type, counter);
	pthread_mutex_destroy(&lock);
}

static void
check_types(void)
{
	pthread_mutexattr_t attr;
	pthread_mutex_t m;

	pthread_mutexattr_init(&attr);

	/* Recursive: the owner locks again; an unlock too many gives EPERM. */
	pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
	pthread_mutex_init(&m, &attr);
	if (pthread_mutex_lock(&m) != 0 || pthread_mutex_lock(&m) != 0 ||
	    pthread_mutex_unlock(&m) != 0 || pthread_mutex_unlock(&m) != 0 ||
	    pthread_mutex_unlock(&m) != EPERM)
		errx(1, "recursive mutex");
	pthread_mutex_destroy(&m);

	/* Errorcheck: a second lock gives EDEADLK, a bad unlock EPERM. */
	pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_ERRORCHECK);
	pthread_mutex_init(&m, &attr);
	if (pthread_mutex_lock(&m) != 0 || pthread_mutex_lock(&m) != EDEADLK ||
	    pthread_mutex_unlock(&m) != 0 || pthread_mutex_unlock(&m) != EPERM)
		errx(1, "errorcheck mutex");
	pthread_mutex_destroy(&m);

	/* Normal: trylock on a locked mutex gives EBUSY. */
	pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_NORMAL);
	pthread_mutex_init(&m, &attr);
	if (pthread_mutex_lock(&m) != 0 || pthread_mutex_trylock(&m) != EBUSY ||
	    pthread_mutex_unlock(&m) != 0)
		errx(1, "normal mutex");
	pthread_mutex_destroy(&m);

	pthread_mutexattr_destroy(&attr);
}

int
main(void)
{
	pthread_attr_t attr;
	pthread_t thread;
	void *ret;

	if (gettid() <= 0)
		errx(1, "gettid");
	check_types();
	contend(PTHREAD_MUTEX_NORMAL);
	contend(PTHREAD_MUTEX_RECURSIVE);
	contend(PTHREAD_MUTEX_ERRORCHECK);
	if (once_count != 1)
		errx(1, "pthread_once: %d calls", once_count);

	if (pthread_create(&thread, NULL, exit_with_value, (void *)42) != 0 ||
	    pthread_join(thread, &ret) != 0 || ret != (void *)42)
		errx(1, "pthread_exit");

	pthread_attr_init(&attr);
	pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
	if (pthread_create(&thread, &attr, detached_main, NULL) != 0)
		errx(1, "pthread_create detached");
	pthread_attr_destroy(&attr);
	pthread_mutex_lock(&done_lock);
	while (detached_done == 0)
		pthread_cond_wait(&done_cond, &done_lock);
	pthread_mutex_unlock(&done_lock);

	printf("threads ok\n");
	return (0);
}
