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
 * FreeBSD overrides for AOSP's jemalloc_internal_defs.h, which was
 * generated on Linux.  The build passes this file to every jemalloc source
 * with -include; the include guard of AOSP's file then stops the second
 * include from jemalloc_preamble.h.
 */

#ifndef JEMALLOC_INTERNAL_DEFS_FREEBSD_H_
#define	JEMALLOC_INTERNAL_DEFS_FREEBSD_H_

#include <jemalloc/internal/jemalloc_internal_defs.h>

/* Use the libc wrappers rather than syscall(2). */
#undef JEMALLOC_USE_SYSCALL

/*
 * There is no /proc/sys/vm/overcommit_memory, and bionic has no
 * sysctlbyname(3) to read vm.overcommit.  Without either, jemalloc assumes
 * no overcommit and decommits with mmap(PROT_NONE).
 */
#undef JEMALLOC_PROC_SYS_VM_OVERCOMMIT_MEMORY

/* FreeBSD has no MADV_HUGEPAGE. */
#undef JEMALLOC_HAVE_MADVISE_HUGE

/*
 * MADV_DONTNEED does not zero anonymous pages on FreeBSD, so jemalloc must
 * not count on it for calloc().  MADV_FREE exists.  bionic's madvise()
 * translates the Android values.
 */
#undef JEMALLOC_PURGE_MADVISE_DONTNEED_ZEROS
#undef JEMALLOC_DEFINE_MADVISE_FREE
#define	JEMALLOC_PURGE_MADVISE_FREE

/* No sched_getcpu(3) yet. */
#undef JEMALLOC_HAVE_SCHED_GETCPU

#endif /* !JEMALLOC_INTERNAL_DEFS_FREEBSD_H_ */
