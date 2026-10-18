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
 * M1 test: the stack protector of bionic-freebsd.
 *
 * With no argument, check that the stack guard is not zero and that TLS
 * slot 5 (TP + 0x28), where the compiler reads the guard, has the same
 * value.  The startup code copies the guard from AT_CANARY.
 *
 * With the argument "overflow", write past a stack buffer.  The check at
 * the function return must call __stack_chk_fail(), which aborts the
 * program with SIGABRT.
 */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern uintptr_t __stack_chk_guard;

static void __attribute__((__noinline__))
overflow(size_t len)
{
	char buf[16];
	size_t i;
	volatile char *p;

	/*
	 * Write one byte at a time.  FORTIFY would stop a memset() before
	 * the stack protector can see the damage.
	 */
	p = buf;
	for (i = 0; i < len; i++)
		p[i] = 'A';
}

int
main(int argc, char **argv)
{
	uintptr_t *tp;

	if (argc > 1 && strcmp(argv[1], "overflow") == 0) {
		/* The length comes from argv, so the compiler cannot see it. */
		overflow(strlen(argv[1]) * 8);
		printf("the stack protector did not trip\n");
		return (1);
	}
	__asm__ __volatile__("mrs %0, tpidr_el0" : "=r"(tp));
	if (__stack_chk_guard == 0) {
		printf("the stack guard is zero\n");
		return (1);
	}
	if (tp[5] != __stack_chk_guard) {
		printf("TLS slot 5 is not the stack guard\n");
		return (1);
	}
	printf("stack guard ok\n");
	return (0);
}
