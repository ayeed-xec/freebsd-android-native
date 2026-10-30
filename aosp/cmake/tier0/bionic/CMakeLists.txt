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
# Builds bionic for the FreeBSD kernel ABI: the system call stubs, libc.a,
# libc.so, the crt objects, ld-android.so, linker64, abi_check and the
# tests.  Source groups and flags follow libc/Android.bp and
# linker/Android.bp, so a file is easy to find in both places.
#
#   cmake -G Ninja -S aosp/cmake/tier0/bionic -B /home/dev/build/tier0 \
#       -DCMAKE_TOOLCHAIN_FILE=config/toolchain/aarch64-freebsd-android37.cmake \
#       -DBIONIC_SRC=/home/dev/aosp/platform_bionic \
#       -DBUILTINS_LIB=/home/dev/build/builtins/lib/freebsd/libclang_rt.builtins-aarch64.a
#   ninja -C /home/dev/build/tier0 && ctest --test-dir /home/dev/build/tier0
#
# linker64 needs libc++ in the bionic sysroot (aosp/cmake/tier0/libcxx.cmake).

cmake_minimum_required(VERSION 3.20)
project(bionic_freebsd_tier0 C CXX ASM)

# libc.so and linker64 are shared objects: build all code with -fPIC, as
# AOSP does.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(BIONIC_SRC "/home/dev/aosp/platform_bionic" CACHE PATH
    "bionic-freebsd checkout (branch freebsd)")
set(AOSP_SYSTEM "/home/dev/aosp/system" CACHE PATH
    "AOSP system/ checkout (core, logging) at the pinned build")
set(SYSCALLS_MASTER "${BIONIC_SRC}/libc/kernel/freebsd/syscalls.master"
    CACHE FILEPATH "syscalls.master of the freebsd-src fork")
set(HOST_CC cc CACHE STRING "FreeBSD compiler for abi_probe")
set(PLATFORM_SDK_VERSION 37 CACHE STRING "Android API level")
set(BUILTINS_LIB "" CACHE FILEPATH
    "libclang_rt.builtins-aarch64.a built from compiler-rt; empty: none")
set(BIONIC_SYSROOT "/home/dev/build/sysroot-bionic-freebsd" CACHE PATH
    "bionic sysroot with libc++ (aosp/cmake/tier0/libcxx.cmake)")
set(AOSP_EXTERNAL "/home/dev/aosp/external" CACHE PATH
    "AOSP external/ checkouts at the pinned build")
set(SCUDO_SRC "${AOSP_EXTERNAL}/scudo" CACHE PATH
    "scudo checkout with the FreeBSD platform patch")
set(GWP_ASAN_SRC "${AOSP_EXTERNAL}/gwp_asan" CACHE PATH
    "GWP-ASan checkout with the FreeBSD platform patch")

find_program(AWK awk REQUIRED)

set(PROJECT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../..")
set(PARITY "${PROJECT_ROOT}/tools/parity")
set(LIBC "${BIONIC_SRC}/libc")
set(GEN "${CMAKE_CURRENT_BINARY_DIR}")
set(PROPINFO "${AOSP_SYSTEM}/core/property_service/libpropertyinfoparser")

# Android code sees the bionic-freebsd headers only, never /usr/include,
# and the Linux-named headers of linux-compat after them.  -O2 and the
# sections flags are bionic's global flags.
add_compile_options(-nostdlibinc -O2 -ffunction-sections -fdata-sections
    -Wall -Werror)
include_directories(SYSTEM "${LIBC}/include" "${LIBC}/include/linux-compat")
include_directories("${LIBC}")

# libc_common_flags and libc_defaults of libc/Android.bp.  Android clang
# makes unwind tables by default.  The -Wno-* flags in the last lines stop
# warnings that clang 22 and the -Wundef of our clang configuration give,
# and AOSP's clang does not.
set(LIBC_FLAGS -D_LIBC=1 -DUSE_SCUDO -Wextra -Wunused -Wno-char-subscripts
    -Wno-deprecated-declarations -Wno-gcc-compat -Wframe-larger-than=2048
    -Wno-reorder-init-list -fno-builtin -fasynchronous-unwind-tables
    $<$<COMPILE_LANGUAGE:C>:-std=gnu99>
    $<$<COMPILE_LANGUAGE:CXX>:-std=gnu++20 -nostdinc++ -fno-exceptions
    -fno-rtti -Wno-c99-designator -Wno-vla-cxx-extension>
    -Wno-undef -Wno-non-c-typedef-for-linkage -Wno-missing-field-initializers
    -Wno-unterminated-string-initialization)
set(LIBC_INCLUDES "${LIBC}/async_safe/include" "${LIBC}/platform"
    "${LIBC}/stdio" "${LIBC}/system_properties/include" "${PROPINFO}/include"
    "${BIONIC_SRC}/libstdc++/include" "${AOSP_SYSTEM}/core/libcutils/include"
    "${AOSP_SYSTEM}/logging/liblog/include"
    "${SCUDO_SRC}/standalone/include" "${GWP_ASAN_SRC}")

function(libc_objects name)
	cmake_parse_arguments(L "" "" "SRCS;FLAGS;INCLUDES" ${ARGN})
	add_library(${name} OBJECT ${L_SRCS})
	target_compile_options(${name} PRIVATE ${LIBC_FLAGS} ${L_FLAGS})
	target_include_directories(${name} PRIVATE ${L_INCLUDES}
	    ${LIBC_INCLUDES})
endfunction()

# System call stubs from SYSCALLS.FREEBSD.TXT.
add_custom_command(OUTPUT "${GEN}/syscalls-arm64.S"
    COMMAND "${AWK}" -f "${PARITY}/parse_syscalls_master.awk"
        stubs "${SYSCALLS_MASTER}" "${LIBC}/SYSCALLS.FREEBSD.TXT"
        > "${GEN}/syscalls-arm64.S"
    DEPENDS "${PARITY}/parse_syscalls_master.awk" "${SYSCALLS_MASTER}"
        "${LIBC}/SYSCALLS.FREEBSD.TXT"
    VERBATIM)

# libc_bootstrap and libc_init_static: the code that runs before TLS and
# the stack guard exist.
libc_objects(libc_bootstrap
    SRCS "${LIBC}/bionic/__libc_init_main_thread.cpp"
        "${LIBC}/bionic/__stack_chk_fail.cpp"
        "${LIBC}/bionic/bionic_call_ifunc_resolver.cpp"
        "${LIBC}/bionic/getauxval.cpp"
        "${LIBC}/bionic/libc_init_mte.cpp"
    FLAGS -fno-stack-protector -ffreestanding)
libc_objects(libc_init_static
    SRCS "${LIBC}/bionic/libc_init_static.cpp"
    FLAGS -fno-stack-protector -ffreestanding)
libc_objects(libc_init_dynamic
    SRCS "${LIBC}/bionic/libc_init_dynamic.cpp"
    FLAGS -fno-stack-protector)

# libc_bionic, libasync_safe and libsystemproperties: only the files that
# the startup code and stdio need.
libc_objects(libc_bionic
    SRCS "${LIBC}/async_safe/async_safe_log.cpp"
        "${LIBC}/bionic/__bionic_get_shell_path.cpp"
        "${LIBC}/bionic/__gnu_basename.cpp"
        "${LIBC}/bionic/__libc_current_sigrtmax.cpp"
        "${LIBC}/bionic/__libc_current_sigrtmin.cpp"
        "${LIBC}/bionic/__cxa_guard.cpp"
        "${LIBC}/bionic/__cxa_thread_atexit_impl.cpp"
        "${LIBC}/bionic/__errno.cpp"
        "${LIBC}/bionic/__progname.cpp"
        "${LIBC}/bionic/abort.cpp"
        "${LIBC}/bionic/accept.cpp"
        "${LIBC}/bionic/access.cpp"
        "${LIBC}/bionic/android_set_abort_message.cpp"
        "${LIBC}/bionic/arpa_inet.cpp"
        "${LIBC}/bionic/assert.cpp"
        "${LIBC}/bionic/atexit.cpp"
        "${LIBC}/bionic/bionic_allocator.cpp"
        "${LIBC}/bionic/bionic_arc4random.cpp"
        "${LIBC}/bionic/bionic_elf_tls.cpp"
        "${LIBC}/bionic/bionic_futex.cpp"
        "${LIBC}/bionic/bionic_netlink.cpp"
        "${LIBC}/bionic/bionic_systrace.cpp"
        "${LIBC}/bionic/bionic_time_conversions.cpp"
        "${LIBC}/bionic/c32rtomb.cpp"
        "${LIBC}/bionic/casecmp.cpp"
        "${LIBC}/bionic/chmod.cpp"
        "${LIBC}/bionic/chown.cpp"
        "${LIBC}/bionic/clock.cpp"
        "${LIBC}/bionic/clock_getcpuclockid.cpp"
        "${LIBC}/bionic/clock_nanosleep.cpp"
        "${LIBC}/bionic/clone.cpp"
        "${LIBC}/bionic/dirent.cpp"
        "${LIBC}/bionic/div.cpp"
        "${LIBC}/bionic/dup.cpp"
        "${LIBC}/bionic/elf_note.cpp"
        "${LIBC}/bionic/env.cpp"
        "${LIBC}/bionic/environ.cpp"
        "${LIBC}/bionic/err.cpp"
        "${LIBC}/bionic/error.cpp"
        "${LIBC}/bionic/eventfd.cpp"
        "${LIBC}/bionic/exit.cpp"
        "${LIBC}/bionic/fork.cpp"
        "${LIBC}/bionic/exec.cpp"
        "${LIBC}/bionic/fcntl.cpp"
        "${LIBC}/bionic/fdsan.cpp"
        "${LIBC}/bionic/fdtrack.cpp"
        "${LIBC}/bionic/fpclassify.cpp"
        "${LIBC}/bionic/ftw.cpp"
        "${LIBC}/bionic/getcwd.cpp"
        "${LIBC}/bionic/getentropy.cpp"
        "${LIBC}/bionic/gethostname.cpp"
        "${LIBC}/bionic/getpagesize.cpp"
        "${LIBC}/bionic/getpgrp.cpp"
        "${LIBC}/bionic/getpid.cpp"
        "${LIBC}/bionic/gettid.cpp"
        "${LIBC}/bionic/heap_tagging.cpp"
        "${LIBC}/bionic/heap_zero_init.cpp"
        "${LIBC}/bionic/iconv.cpp"
        "${LIBC}/bionic/ifaddrs.cpp"
        "${LIBC}/bionic/inotify_init.cpp"
        "${LIBC}/bionic/ioctl.cpp"
        "${LIBC}/bionic/isatty.cpp"
        "${LIBC}/bionic/killpg.cpp"
        "${LIBC}/bionic/lchown.cpp"
        "${LIBC}/bionic/langinfo.cpp"
        "${LIBC}/bionic/libc_init_common.cpp"
        "${LIBC}/bionic/libgen.cpp"
        "${LIBC}/bionic/link.cpp"
        "${LIBC}/bionic/locale.cpp"
        "${LIBC}/bionic/lockf.cpp"
        "${LIBC}/bionic/lstat.cpp"
        "${LIBC}/bionic/mbrtoc32.cpp"
        "${LIBC}/bionic/memset_explicit.cpp"
        "${LIBC}/bionic/mkdir.cpp"
        "${LIBC}/bionic/mknod.cpp"
        "${LIBC}/bionic/mntent.cpp"
        "${LIBC}/bionic/new.cpp"
        "${LIBC}/bionic/NetdClientDispatch.cpp"
        "${LIBC}/bionic/netdb.cpp"
        "${LIBC}/bionic/net_if.cpp"
        "${LIBC}/bionic/netinet_in.cpp"
        "${LIBC}/bionic/open.cpp"
        "${LIBC}/bionic/pathconf.cpp"
        "${LIBC}/bionic/pause.cpp"
        "${LIBC}/bionic/pipe.cpp"
        "${LIBC}/bionic/posix_madvise.cpp"
        "${LIBC}/bionic/posix_timers.cpp"
        "${LIBC}/bionic/poll.cpp"
        "${LIBC}/bionic/pthread_atfork.cpp"
        "${LIBC}/bionic/pthread_attr.cpp"
        "${LIBC}/bionic/pthread_barrier.cpp"
        "${LIBC}/bionic/pthread_cond.cpp"
        "${LIBC}/bionic/pthread_create.cpp"
        "${LIBC}/bionic/pthread_detach.cpp"
        "${LIBC}/bionic/pthread_getaffinity.cpp"
        "${LIBC}/bionic/pthread_getcpuclockid.cpp"
        "${LIBC}/bionic/pthread_getschedparam.cpp"
        "${LIBC}/bionic/pthread_gettid_np.cpp"
        "${LIBC}/bionic/pthread_exit.cpp"
        "${LIBC}/bionic/pthread_internal.cpp"
        "${LIBC}/bionic/pthread_join.cpp"
        "${LIBC}/bionic/pthread_key.cpp"
        "${LIBC}/bionic/pthread_kill.cpp"
        "${LIBC}/bionic/pthread_mutex.cpp"
        "${LIBC}/bionic/pthread_once.cpp"
        "${LIBC}/bionic/pthread_rwlock.cpp"
        "${LIBC}/bionic/pthread_self.cpp"
        "${LIBC}/bionic/pthread_setaffinity.cpp"
        "${LIBC}/bionic/pthread_setschedparam.cpp"
        "${LIBC}/bionic/pthread_setname_np.cpp"
        "${LIBC}/bionic/pthread_spinlock.cpp"
        "${LIBC}/bionic/pthread_sigqueue.cpp"
        "${LIBC}/bionic/pty.cpp"
        "${LIBC}/bionic/raise.cpp"
        "${LIBC}/bionic/rand.cpp"
        "${LIBC}/bionic/readlink.cpp" "${LIBC}/bionic/recv.cpp"
        "${LIBC}/bionic/recvmsg.cpp"
        "${LIBC}/bionic/rename.cpp"
        "${LIBC}/bionic/rmdir.cpp"
        "${LIBC}/bionic/sched_cpucount.cpp"
        "${LIBC}/bionic/sched_getaffinity.cpp"
        "${LIBC}/bionic/semaphore.cpp" "${LIBC}/bionic/send.cpp"
        "${LIBC}/bionic/setjmp_cookie.cpp"
        "${LIBC}/bionic/sigaction.cpp"
        "${LIBC}/bionic/signal.cpp"
        "${LIBC}/bionic/sleep.cpp"
        "${LIBC}/bionic/sigprocmask.cpp"
        "${LIBC}/bionic/socketpair.cpp"
        "${LIBC}/bionic/stat.cpp"
        "${LIBC}/bionic/strerror.cpp"
        "${LIBC}/bionic/strsignal.cpp"
        "${LIBC}/bionic/strtod.cpp"
        "${LIBC}/bionic/strtold.cpp"
        "${LIBC}/bionic/swab.cpp"
        "${LIBC}/bionic/symlink.cpp"
        "${LIBC}/bionic/sys_epoll.cpp"
        "${LIBC}/bionic/sys_statvfs.cpp"
        "${LIBC}/bionic/sysconf.cpp"
        "${LIBC}/bionic/sysinfo.cpp"
        "${LIBC}/bionic/syslog.cpp"
        "${LIBC}/bionic/sysprop_helpers.cpp"
        "${LIBC}/bionic/string.cpp"
        "${LIBC}/bionic/strtol.cpp"
        "${LIBC}/bionic/system_property_api.cpp"
        "${LIBC}/bionic/system_property_set.cpp"
        "${LIBC}/bionic/termios.cpp"
        "${LIBC}/bionic/time.cpp"
        "${LIBC}/bionic/tmpfile.cpp"
        "${LIBC}/bionic/unlink.cpp"
        "${LIBC}/bionic/usleep.cpp"
        "${LIBC}/bionic/utmp.cpp"
        "${LIBC}/bionic/vdso.cpp"
        "${LIBC}/bionic/wait.cpp"
        "${LIBC}/bionic/wchar.cpp"
        "${LIBC}/bionic/wctype.cpp"
        "${LIBC}/bionic/wcstod.cpp"
        "${LIBC}/bionic/wcwidth.cpp"
        "${LIBC}/stdio/fmemopen.cpp"
        "${LIBC}/stdio/stdio.cpp"
        "${LIBC}/stdio/stdio_ext.cpp"
        "${LIBC}/stdio/parsefloat.c"
        "${LIBC}/stdio/vfscanf.cpp"
        "${LIBC}/stdio/vfwscanf.cpp"
        "${LIBC}/system_properties/context_node.cpp"
        "${LIBC}/system_properties/contexts_serialized.cpp"
        "${LIBC}/system_properties/contexts_split.cpp"
        "${LIBC}/system_properties/prop_area.cpp"
        "${LIBC}/system_properties/prop_info.cpp"
        "${LIBC}/system_properties/system_properties.cpp"
        "${PROPINFO}/property_info_parser.cpp")

# getpwnam(3), getgrnam(3) and the other passwd and group functions: the
# Android ids of libcutils, then the passwd and group files of the
# partitions.  The table of ids is generated as Android's
# generated_android_ids rule does.
set(CUTILS_INCLUDE "${AOSP_SYSTEM}/core/libcutils/include")
set(AID_HEADER "${CUTILS_INCLUDE}/private/android_filesystem_config.h")
add_custom_command(OUTPUT "${GEN}/generated_android_ids.h"
    COMMAND "${AWK}" -f "${PROJECT_ROOT}/tools/fs_config/gen_android_ids.awk"
        "${AID_HEADER}" > "${GEN}/generated_android_ids.h"
    DEPENDS "${PROJECT_ROOT}/tools/fs_config/gen_android_ids.awk"
        "${AID_HEADER}"
    VERBATIM)
libc_objects(libc_grp_pwd
    SRCS "${LIBC}/bionic/grp_pwd.cpp" "${LIBC}/bionic/grp_pwd_file.cpp"
        "${GEN}/generated_android_ids.h"
    INCLUDES "${GEN}")

# The _chk functions.  Build them without FORTIFY, or they would call
# themselves.
libc_objects(libc_fortify
    SRCS "${LIBC}/bionic/fortify.cpp"
        "${LIBC}/arch-arm64/string/__memcpy_chk.S"
        "${LIBC}/arch-arm64/string/__memset_chk.S"
    FLAGS -U_FORTIFY_SOURCE -D__BIONIC_DECLARE_FORTIFY_HELPERS)

# FreeBSD-only code.  linker64 has its own malloc (linker_memory.cpp).
libc_objects(libc_freebsd_port
    SRCS "${LIBC}/arch-arm64/bionic/_exit_with_stack_teardown.S"
        "${LIBC}/arch-arm64/freebsd/fork.S"
        "${LIBC}/arch-arm64/bionic/setjmp.S"
        "${LIBC}/arch-arm64/bionic/syscall.S"
        "${LIBC}/arch-arm64/bionic/vfork.S"
        "${LIBC}/bionic/freebsd/__set_errno_from_freebsd.c"
        "${LIBC}/bionic/freebsd/bsearch.c"
        "${LIBC}/bionic/freebsd/capability.c"
        "${LIBC}/bionic/freebsd/elf_aux_info.cpp"
        "${LIBC}/bionic/freebsd/getdents.c"
        "${LIBC}/bionic/freebsd/icu4x_ascii.cpp"
        "${LIBC}/bionic/freebsd/inotify.c"
        "${LIBC}/bionic/freebsd/madvise.c"
        "${LIBC}/bionic/freebsd/memfd_create.c"
        "${LIBC}/bionic/freebsd/mlock2.c"
        "${LIBC}/bionic/freebsd/mount.c"
        "${LIBC}/bionic/freebsd/mmap.c"
        "${LIBC}/bionic/freebsd/mremap.c"
        "${LIBC}/bionic/freebsd/no_equivalent.c"
        "${LIBC}/bionic/freebsd/mprotect.c"
        "${LIBC}/bionic/freebsd/posix_fallocate.c"
        "${LIBC}/bionic/freebsd/prctl.c"
        "${LIBC}/bionic/freebsd/priority.c"
        "${LIBC}/bionic/freebsd/prlimit.c"
        "${LIBC}/bionic/freebsd/qsort.c"
        "${LIBC}/bionic/freebsd/recvmmsg.c"
        "${LIBC}/bionic/freebsd/recvmsg.c"
        "${LIBC}/bionic/freebsd/sched.c"
        "${LIBC}/bionic/freebsd/sendmmsg.c"
        "${LIBC}/bionic/freebsd/sockopt.c"
        "${LIBC}/bionic/freebsd/statfs.c"
        "${LIBC}/bionic/freebsd/swap.c"
        "${LIBC}/bionic/freebsd/sysctlbyname.c"
        "${LIBC}/bionic/freebsd/sysinfo.c"
        "${LIBC}/bionic/freebsd/timekeep.c"
        "${LIBC}/bionic/freebsd/umount.c"
        "${LIBC}/bionic/freebsd/uname.c"
        "${LIBC}/bionic/freebsd/xattr.c")
# FreeBSD's realpath(3) and struct statfs have PATH_MAX buffers.  mount()
# copies the data string to a 1,024-byte buffer and builds the nmount(2)
# options in 64 iovecs.
set_source_files_properties(
    "${LIBC}/upstream-freebsd/lib/libc/stdlib/realpath.c" PROPERTIES
    COMPILE_OPTIONS -Wframe-larger-than=4096)
set_source_files_properties("${LIBC}/bionic/freebsd/statfs.c"
    "${LIBC}/bionic/freebsd/mount.c" PROPERTIES
    COMPILE_OPTIONS -Wframe-larger-than=4096)
# iconv.cpp gives a char32_t below 0x10000 to a char16_t parameter, and
# clang 22 warns about that conversion.
set_source_files_properties("${LIBC}/bionic/iconv.cpp" PROPERTIES
    COMPILE_OPTIONS -Wno-character-conversion)

# The allocator sources and flags follow their Android.bp files.  The
# malloc front end follows libc/Android.bp for static and shared libc.
set(SCUDO_SRCS checksum common condition_variable_linux crc32_hw flags
    flags_parser freebsd linux mem_map mem_map_linux release report
    report_linux string_utils timing wrappers_c_bionic)
list(TRANSFORM SCUDO_SRCS PREPEND "${SCUDO_SRC}/standalone/")
list(TRANSFORM SCUDO_SRCS APPEND ".cpp")
add_library(scudo OBJECT ${SCUDO_SRCS})
target_include_directories(scudo PRIVATE "${LIBC}" "${SCUDO_SRC}/config"
    "${SCUDO_SRC}/standalone/include" "${LIBC}/platform"
    "${BIONIC_SRC}/libstdc++/include")
# The compiler configuration adds -Wundef; Android's scudo flags do not.
target_compile_options(scudo PRIVATE -std=gnu++20 -O3 -fno-rtti
    -fno-stack-protector -nostdinc++ -fno-exceptions -mcrc
    -Wall -Wextra -Wunused -Wno-unused-result -Wno-undef -Wconversion
    -Werror=pointer-to-int-cast -Werror=int-to-pointer-cast
    -Werror=thread-safety -Werror=type-limits -Werror
    -DSCUDO_USE_CUSTOM_CONFIG -D_BIONIC=1
    -DSCUDO_HAS_PLATFORM_TLS_SLOT -DSCUDO_MIN_ALIGNMENT_LOG=4
    -DHAVE_ANDROID_UNSAFE_FRAME_POINTER_CHASE -DSCUDO_ENABLE_TRACING)
set(GWP_ASAN_SRCS common crash_handler guarded_pool_allocator
    platform_specific/common_posix
    platform_specific/guarded_pool_allocator_posix
    platform_specific/mutex_posix platform_specific/utilities_posix
    stack_trace_compressor)
list(TRANSFORM GWP_ASAN_SRCS PREPEND "${GWP_ASAN_SRC}/gwp_asan/")
list(TRANSFORM GWP_ASAN_SRCS APPEND ".cpp")
add_library(gwp_asan OBJECT ${GWP_ASAN_SRCS})
target_include_directories(gwp_asan PRIVATE "${GWP_ASAN_SRC}"
    "${BIONIC_SRC}/libstdc++/include")
target_compile_options(gwp_asan PRIVATE -std=gnu++20 -nostdinc++
    -fno-exceptions -fno-rtti -fno-emulated-tls)
set(MALLOC_COMMON "${LIBC}/bionic/android_mallopt.cpp"
    "${LIBC}/bionic/malloc_common.cpp" "${LIBC}/bionic/malloc_limit.cpp"
    "${LIBC}/bionic/gwp_asan_wrappers.cpp"
    "${LIBC}/bionic/android_unsafe_frame_pointer_chase.cpp")
libc_objects(libc_malloc_static SRCS ${MALLOC_COMMON} FLAGS -DLIBC_STATIC)
libc_objects(libc_malloc_shared SRCS ${MALLOC_COMMON}
    "${LIBC}/bionic/malloc_common_dynamic.cpp"
    "${LIBC}/bionic/malloc_heapprofd.cpp")
set(MALLOC_STATIC $<TARGET_OBJECTS:scudo> $<TARGET_OBJECTS:gwp_asan>
    $<TARGET_OBJECTS:libc_malloc_static>)
set(MALLOC_SHARED $<TARGET_OBJECTS:scudo> $<TARGET_OBJECTS:gwp_asan>
    $<TARGET_OBJECTS:libc_malloc_shared>)

# libc_openbsd and libc_gdtoa: stdio internals, arc4random and dtoa.
set(OPENBSD "${LIBC}/upstream-openbsd")
libc_objects(libc_openbsd
    SRCS "${LIBC}/stdio/vfprintf.cpp"
        "${LIBC}/stdio/vfwprintf.cpp"
        "${OPENBSD}/lib/libc/crypt/arc4random.c"
        "${OPENBSD}/lib/libc/crypt/arc4random_uniform.c"
        "${OPENBSD}/lib/libc/gen/alarm.c"
        "${OPENBSD}/lib/libc/gen/daemon.c"
        "${OPENBSD}/lib/libc/gen/fnmatch.c"
        "${LIBC}/bionic/fts.c"
        "${OPENBSD}/lib/libc/locale/btowc.c"
        "${OPENBSD}/lib/libc/locale/mbrlen.c"
        "${OPENBSD}/lib/libc/locale/mbstowcs.c"
        "${OPENBSD}/lib/libc/locale/mbtowc.c"
        "${OPENBSD}/lib/libc/locale/wctob.c"
        "${OPENBSD}/lib/libc/net/base64.c"
        "${OPENBSD}/lib/libc/net/inet_ntoa.c"
        "${OPENBSD}/lib/libc/net/inet_ntop.c"
        "${OPENBSD}/lib/libc/net/inet_pton.c"
        "${OPENBSD}/lib/libc/net/res_random.c"
        "${OPENBSD}/lib/libc/stdio/fgetwc.c"
        "${OPENBSD}/lib/libc/stdio/flags.c"
        "${OPENBSD}/lib/libc/stdio/fputwc.c"
        "${OPENBSD}/lib/libc/stdio/fvwrite.c"
        "${OPENBSD}/lib/libc/stdio/getdelim.c"
        "${OPENBSD}/lib/libc/stdio/mktemp.c"
        "${OPENBSD}/lib/libc/stdio/open_memstream.c"
        "${OPENBSD}/lib/libc/stdio/ungetc.c"
        "${OPENBSD}/lib/libc/stdio/ungetwc.c"
        "${OPENBSD}/lib/libc/stdio/vswprintf.c"
        "${OPENBSD}/lib/libc/stdio/wbuf.c"
        "${OPENBSD}/lib/libc/stdio/wsetup.c"
        "${OPENBSD}/lib/libc/stdlib/recallocarray.c"
        "${OPENBSD}/lib/libc/string/strcasestr.c"
    FLAGS -Wno-sign-compare -Wno-unused-parameter -include openbsd-compat.h
    INCLUDES "${LIBC}/private" "${OPENBSD}/android/include"
        "${OPENBSD}/lib/libc/gdtoa" "${OPENBSD}/lib/libc/include"
        "${OPENBSD}/lib/libc/stdio")
libc_objects(libc_openbsd_large_stack
    SRCS "${OPENBSD}/lib/libc/string/memmem.c"
        "${OPENBSD}/lib/libc/string/strstr.c"
    FLAGS -Wno-sign-compare -Wframe-larger-than=5000
        -include openbsd-compat.h
    INCLUDES "${OPENBSD}/android/include")
libc_objects(libc_gdtoa
    SRCS "${OPENBSD}/android/gdtoa_support.cpp"
        "${OPENBSD}/lib/libc/gdtoa/dmisc.c"
        "${OPENBSD}/lib/libc/gdtoa/dtoa.c"
        "${OPENBSD}/lib/libc/gdtoa/gdtoa.c"
        "${OPENBSD}/lib/libc/gdtoa/gethex.c"
        "${OPENBSD}/lib/libc/gdtoa/gmisc.c"
        "${OPENBSD}/lib/libc/gdtoa/hd_init.c"
        "${OPENBSD}/lib/libc/gdtoa/hdtoa.c"
        "${OPENBSD}/lib/libc/gdtoa/hexnan.c"
        "${OPENBSD}/lib/libc/gdtoa/ldtoa.c"
        "${OPENBSD}/lib/libc/gdtoa/misc.c"
        "${OPENBSD}/lib/libc/gdtoa/smisc.c"
        "${OPENBSD}/lib/libc/gdtoa/strtod.c"
        "${OPENBSD}/lib/libc/gdtoa/strtodg.c"
        "${OPENBSD}/lib/libc/gdtoa/strtof.c"
        "${OPENBSD}/lib/libc/gdtoa/strtord.c"
        "${OPENBSD}/lib/libc/gdtoa/strtorQ.c"
        "${OPENBSD}/lib/libc/gdtoa/sum.c"
        "${OPENBSD}/lib/libc/gdtoa/ulp.c"
    FLAGS -Wno-sign-compare -include openbsd-compat.h
    INCLUDES "${LIBC}/private" "${OPENBSD}/android/include"
        "${OPENBSD}/lib/libc/include")

# String functions: FreeBSD's portable C versions stand in for
# external/arm-optimized-routines, which tier 0 does not have yet.
set(FBSD_STRING "${LIBC}/upstream-freebsd/lib/libc/string")
libc_objects(libc_freebsd_string
    SRCS "${FBSD_STRING}/bcmp.c" "${FBSD_STRING}/memchr.c"
        "${FBSD_STRING}/memcmp.c" "${FBSD_STRING}/memrchr.c"
        "${FBSD_STRING}/memcpy.c" "${FBSD_STRING}/memmove.c"
        "${FBSD_STRING}/memset.c" "${FBSD_STRING}/strchr.c"
        "${FBSD_STRING}/strchrnul.c" "${FBSD_STRING}/strcmp.c"
        "${FBSD_STRING}/strcpy.c" "${FBSD_STRING}/strcspn.c"
        "${FBSD_STRING}/strlen.c" "${FBSD_STRING}/strncmp.c"
        "${FBSD_STRING}/strnlen.c" "${FBSD_STRING}/strrchr.c"
        "${FBSD_STRING}/stpcpy.c" "${FBSD_STRING}/strspn.c"
        "${FBSD_STRING}/wcscmp.c" "${FBSD_STRING}/wmemchr.c"
        "${FBSD_STRING}/wcslcpy.c" "${FBSD_STRING}/wcslen.c"
        "${FBSD_STRING}/wcsnlen.c" "${FBSD_STRING}/wcsspn.c"
        "${FBSD_STRING}/wcsncmp.c" "${FBSD_STRING}/wcsstr.c"
        "${FBSD_STRING}/wmemcmp.c"
    FLAGS -Wno-sign-compare -Wno-unused-parameter -include freebsd-compat.h
    INCLUDES "${LIBC}/upstream-freebsd/android/include")

# getopt_long(3) as on Android, and FreeBSD's realpath(3) on __realpathat(2)
# in place of bionic's realpath.cpp, which reads /proc/self/fd.
libc_objects(libc_freebsd
    SRCS "${LIBC}/upstream-freebsd/lib/libc/stdlib/getopt_long.c"
        "${LIBC}/upstream-freebsd/lib/libc/stdlib/realpath.c"
    FLAGS -Wno-sign-compare -Wno-unused-parameter -include freebsd-compat.h
    INCLUDES "${LIBC}/upstream-freebsd/android/include")

# ldexp(3) is libm's scalbn() under another name, as libc_freebsd_ldexp of
# libc/Android.bp builds it.
libc_objects(libc_freebsd_ldexp
    SRCS "${BIONIC_SRC}/libm/upstream-freebsd/lib/msun/src/s_scalbn.c"
    FLAGS -Dscalbn=ldexp)

# nice(3), random(3) and regex(3) come from NetBSD, as on Android.
libc_objects(libc_netbsd
    SRCS "${LIBC}/upstream-netbsd/common/lib/libc/stdlib/random.c"
        "${LIBC}/upstream-netbsd/lib/libc/gen/nice.c"
        "${LIBC}/upstream-netbsd/lib/libc/inet/nsap_addr.c"
        "${LIBC}/upstream-netbsd/lib/libc/regex/regcomp.c"
        "${LIBC}/upstream-netbsd/lib/libc/regex/regerror.c"
        "${LIBC}/upstream-netbsd/lib/libc/regex/regexec.c"
        "${LIBC}/upstream-netbsd/lib/libc/regex/regfree.c"
    FLAGS -Wno-sign-compare -Wno-unused-parameter -DPOSIX_MISTAKE
        -include netbsd-compat.h
    INCLUDES "${LIBC}/upstream-netbsd/android/include"
        "${LIBC}/upstream-netbsd/lib/libc/include")

# The complete resolver group, with the flags of libc_dns in Android.bp.
file(GLOB_RECURSE LIBC_DNS_SRCS CONFIGURE_DEPENDS "${LIBC}/dns/*.c*")
libc_objects(libc_dns
    SRCS ${LIBC_DNS_SRCS}
        "${LIBC}/upstream-netbsd/lib/libc/isc/ev_streams.c"
        "${LIBC}/upstream-netbsd/lib/libc/isc/ev_timers.c"
    FLAGS -DANDROID_CHANGES -DINET6 -Wno-unused-parameter
        -include netbsd-compat.h -Wframe-larger-than=66000
    INCLUDES "${LIBC}/dns/include" "${LIBC}/private"
        "${LIBC}/upstream-netbsd/lib/libc/include"
        "${LIBC}/upstream-netbsd/android/include")

# libc_tzcode: time zones, strftime and strptime.
libc_objects(libc_tzcode
    SRCS "${LIBC}/tzcode/bionic.cpp" "${LIBC}/tzcode/localtime.c"
        "${LIBC}/tzcode/strftime.c" "${LIBC}/tzcode/strptime.c"
        "${OPENBSD}/lib/libc/locale/_def_time.c"
        "${LIBC}/upstream-freebsd/lib/libc/locale/wcsftime.c"
    FLAGS -Wno-tautological-constant-out-of-range-compare
        -Wno-unused-parameter -DALL_STATE -DSTD_INSPIRED -DTHREAD_SAFE=1
        -DTM_GMTOFF=tm_gmtoff -DTZDEFAULT=NULL
        "-DTZDIR=\"/system/usr/share/zoneinfo\"" -DHAVE_POSIX_DECLS=0
        -DUSG_COMPAT=2 -DHAVE_TZNAME=2 -DHAVE_STDBOOL_H "-DWILDABBR=\"\""
        -Dlint
    INCLUDES "${LIBC}/tzcode" "${LIBC}/upstream-freebsd/android/include")

# libc_common of libc/Android.bp.
set(LIBC_COMMON "${GEN}/syscalls-arm64.S"
    $<TARGET_OBJECTS:libc_bootstrap>
    $<TARGET_OBJECTS:libc_bionic>
    $<TARGET_OBJECTS:libc_dns>
    $<TARGET_OBJECTS:libc_grp_pwd>
    $<TARGET_OBJECTS:libc_fortify>
    $<TARGET_OBJECTS:libc_freebsd_port>
    $<TARGET_OBJECTS:libc_openbsd>
    $<TARGET_OBJECTS:libc_openbsd_large_stack>
    $<TARGET_OBJECTS:libc_gdtoa>
    $<TARGET_OBJECTS:libc_freebsd_string>
    $<TARGET_OBJECTS:libc_freebsd>
    $<TARGET_OBJECTS:libc_freebsd_ldexp>
    $<TARGET_OBJECTS:libc_netbsd>
    $<TARGET_OBJECTS:libc_tzcode>)
add_library(c_static STATIC ${LIBC_COMMON}
    $<TARGET_OBJECTS:libc_init_static> ${MALLOC_STATIC})
set_target_properties(c_static PROPERTIES OUTPUT_NAME c)
# libc_nomalloc: the C library of linker64.
add_library(c_nomalloc STATIC ${LIBC_COMMON}
    $<TARGET_OBJECTS:libc_init_static>)

# crt objects.  The code before TLS setup must not use the stack
# protector, because the guard is in TLS (slot 5).
add_library(crt_parts OBJECT
    "${LIBC}/arch-common/bionic/crtbrand.S"
    "${LIBC}/arch-common/freebsd/crtbrand_freebsd.S")
target_compile_definitions(crt_parts PRIVATE
    PLATFORM_SDK_VERSION=${PLATFORM_SDK_VERSION})
add_library(crtbegin_static_o OBJECT
    "${LIBC}/arch-common/bionic/crtbegin.c")
target_compile_definitions(crtbegin_static_o PRIVATE CRTBEGIN_STATIC)
target_compile_options(crtbegin_static_o PRIVATE -fno-stack-protector)
add_library(crtbegin_dynamic_o OBJECT
    "${LIBC}/arch-common/bionic/crtbegin.c")
target_compile_options(crtbegin_dynamic_o PRIVATE -fno-stack-protector)
add_library(crtend_o OBJECT "${LIBC}/arch-common/bionic/crtend.S")
# crtbegin_so.o and crtend_so.o: for shared objects other than libc.so.
add_library(crtbegin_so_o OBJECT "${LIBC}/arch-common/bionic/crtbegin_so.c")
target_compile_options(crtbegin_so_o PRIVATE -fno-stack-protector)
add_library(crtend_so_o OBJECT "${LIBC}/arch-common/bionic/crtend_so.S")

foreach(crt crtbegin_static crtbegin_dynamic crtbegin_so)
	add_custom_command(OUTPUT "${GEN}/${crt}.o"
	    COMMAND "${CMAKE_C_COMPILER}" "--config=${ANDROID_CLANG_CFG}"
	        -nostdlib -fuse-ld=lld -Wl,-r -o "${GEN}/${crt}.o"
	        "$<TARGET_OBJECTS:${crt}_o>" "$<TARGET_OBJECTS:crt_parts>"
	    DEPENDS "$<TARGET_OBJECTS:${crt}_o>" "$<TARGET_OBJECTS:crt_parts>"
	    COMMAND_EXPAND_LISTS VERBATIM)
endforeach()
foreach(crt crtend crtend_so)
	add_custom_command(OUTPUT "${GEN}/${crt}.o"
	    COMMAND "${CMAKE_COMMAND}" -E copy "$<TARGET_OBJECTS:${crt}_o>"
	        "${GEN}/${crt}.o"
	    DEPENDS "$<TARGET_OBJECTS:${crt}_o>" VERBATIM)
endforeach()
add_custom_target(crt ALL DEPENDS "${GEN}/crtbegin_static.o"
    "${GEN}/crtbegin_dynamic.o" "${GEN}/crtbegin_so.o" "${GEN}/crtend.o"
    "${GEN}/crtend_so.o")

set(LINKER "${BIONIC_SRC}/linker")
set(SO_LINK_OPTIONS -nostdlib -fuse-ld=lld -Wl,--no-undefined
    -Wl,--gc-sections)

# ld-android.so: the stub that libc.so links against.  At run time,
# linker64 itself provides these symbols under this name.
add_library(ld_android SHARED "${LINKER}/ld_android.cpp")
set_target_properties(ld_android PROPERTIES PREFIX "" OUTPUT_NAME ld-android)
target_compile_options(ld_android PRIVATE -Wextra -Wunused -nostdinc++)
target_link_options(ld_android PRIVATE -nostdlib -fuse-ld=lld
    "-Wl,--version-script=${LINKER}/linker.generic.map")

# libdl.so: a shim over the __loader_* functions of linker64.  It and
# libdl_android.so have no crt objects (nocrt in libdl/Android.bp), so they
# get the FreeBSD ABI note directly, as libc.so and linker64 do.
add_library(dl_shared SHARED "${BIONIC_SRC}/libdl/libdl.cpp"
    "${BIONIC_SRC}/libdl/libdl_cfi.cpp"
    "${LIBC}/arch-common/freebsd/crtbrand_freebsd.S")
set_target_properties(dl_shared PROPERTIES OUTPUT_NAME dl SKIP_BUILD_RPATH ON)
target_compile_options(dl_shared PRIVATE -Wextra -Wunused -nostdinc++
    -std=gnu++20)
target_link_options(dl_shared PRIVATE ${SO_LINK_OPTIONS} -Wl,-soname,libdl.so)
target_link_libraries(dl_shared PRIVATE ld_android)

# libdl_android.so wraps the platform-only __loader_* functions.
add_library(dl_android SHARED "${BIONIC_SRC}/libdl/libdl_android.cpp"
    "${LIBC}/arch-common/freebsd/crtbrand_freebsd.S")
set_target_properties(dl_android PROPERTIES OUTPUT_NAME dl_android
    SKIP_BUILD_RPATH ON)
target_compile_options(dl_android PRIVATE -Wextra -Wunused -nostdinc++
    -std=gnu++20)
target_link_options(dl_android PRIVATE ${SO_LINK_OPTIONS}
    -Wl,-soname,libdl_android.so)
target_link_libraries(dl_android PRIVATE ld_android)

# libc.so: libc_common, the dynamic startup, the allocator and
# libc_sources_shared.  There is no version script yet (libc.map.txt needs
# bionic's generate-version-script).
libc_objects(libc_sources_shared
    SRCS "${LIBC}/arch-common/bionic/crtbegin_so.c"
        "${LIBC}/arch-common/freebsd/crtbrand_freebsd.S"
        "${LIBC}/bionic/android_profiling_dynamic.cpp"
        "${LIBC}/bionic/NetdClient.cpp"
        "${LIBC}/arch-common/bionic/crtend_so.S")
set_source_files_properties("${LIBC}/arch-common/bionic/crtbegin_so.c"
    PROPERTIES COMPILE_OPTIONS -fno-stack-protector)
add_library(c_shared SHARED ${LIBC_COMMON}
    $<TARGET_OBJECTS:libc_init_dynamic> ${MALLOC_SHARED}
    $<TARGET_OBJECTS:libc_sources_shared>)
set_target_properties(c_shared PROPERTIES OUTPUT_NAME c SKIP_BUILD_RPATH ON)
target_link_options(c_shared PRIVATE ${SO_LINK_OPTIONS} -Wl,-soname,libc.so)
target_link_libraries(c_shared PRIVATE ld_android dl_shared dl_android)
if(BUILTINS_LIB)
	target_link_libraries(c_shared PRIVATE "${BUILTINS_LIB}")
endif()

# The static libraries of linker64 (linker_defaults of
# linker/Android.bp): libbase, liblog, libziparchive and zlib.  They are
# C++ code that uses libc++ from the bionic sysroot.
set(CXX_INCLUDE "${BIONIC_SYSROOT}/usr/include/c++/v1")
# Once libc++ is in the sysroot, CMake finds this directory among the
# compiler's implicit ones and leaves out its -isystem, but -nostdlibinc
# takes it away again.  Keep it explicit.
list(REMOVE_ITEM CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES "${CXX_INCLUDE}")
# AOSP's global flags for clang 22 warnings that AOSP code still gives.
set(AOSP_CXX_FLAGS -fno-exceptions -Wno-vla-cxx-extension
    -Wno-c99-designator -Wno-missing-field-initializers
    -Wno-non-c-typedef-for-linkage)
set(LIBBASE "${AOSP_SYSTEM}/libbase")
set(LIBLOG "${AOSP_SYSTEM}/logging/liblog")
set(ZIPARCHIVE "${AOSP_SYSTEM}/libziparchive")
function(aosp_library name)
	cmake_parse_arguments(L "" "" "SRCS;FLAGS;INCLUDES" ${ARGN})
	add_library(${name} STATIC ${L_SRCS})
	target_include_directories(${name} SYSTEM BEFORE PRIVATE
	    "${CXX_INCLUDE}")
	target_include_directories(${name} PRIVATE ${L_INCLUDES})
	# NDEBUG as in AOSP release builds: ALOGV() compiles to nothing.
	target_compile_options(${name} PRIVATE -D_FILE_OFFSET_BITS=64 -DNDEBUG
	    "$<$<COMPILE_LANGUAGE:CXX>:${AOSP_CXX_FLAGS}>" ${L_FLAGS})
endfunction()

include(zlib.cmake)
# libbase has fmtlib in it (whole_static_libs), so programs that link base
# get fmtlib too.
set(FMTLIB "${AOSP_EXTERNAL}/fmtlib")
aosp_library(fmtlib
    SRCS "${FMTLIB}/src/format.cc"
    FLAGS -fno-exceptions -UNDEBUG
    INCLUDES "${FMTLIB}/include")
aosp_library(base
    SRCS "${LIBBASE}/chrono_utils.cpp" "${LIBBASE}/cmsg.cpp"
        "${LIBBASE}/file.cpp" "${LIBBASE}/hex.cpp" "${LIBBASE}/logging.cpp"
        "${LIBBASE}/mapped_file.cpp" "${LIBBASE}/parsebool.cpp"
        "${LIBBASE}/parsenetaddress.cpp" "${LIBBASE}/posix_strerror_r.cpp"
        "${LIBBASE}/process.cpp" "${LIBBASE}/properties.cpp"
        "${LIBBASE}/result.cpp" "${LIBBASE}/stringprintf.cpp"
        "${LIBBASE}/strings.cpp" "${LIBBASE}/threads.cpp"
        "${LIBBASE}/test_utils.cpp" "${LIBBASE}/errors_unix.cpp"
    FLAGS -std=gnu++23 -Wextra -Wexit-time-destructors
    INCLUDES "${LIBBASE}/include" "${LIBLOG}/include" "${FMTLIB}/include")
target_link_libraries(base INTERFACE fmtlib)
aosp_library(log
    SRCS "${LIBLOG}/log_event_list.cpp" "${LIBLOG}/log_event_write.cpp"
        "${LIBLOG}/logger_name.cpp" "${LIBLOG}/logger_read.cpp"
        "${LIBLOG}/logger_write.cpp" "${LIBLOG}/logprint.cpp"
        "${LIBLOG}/properties.cpp" "${LIBLOG}/event_tag_map.cpp"
        "${LIBLOG}/log_time.cpp" "${LIBLOG}/pmsg_reader.cpp"
        "${LIBLOG}/pmsg_writer.cpp" "${LIBLOG}/logd_reader.cpp"
        "${LIBLOG}/logd_writer.cpp"
    FLAGS -std=gnu++20 -DLIBLOG_LOG_TAG=1006
        -DSNET_EVENT_LOG_TAG=1397638484 -DANDROID_DEBUGGABLE=0
    INCLUDES "${LIBLOG}/include" "${LIBBASE}/include"
        "${AOSP_SYSTEM}/core/libcutils/include"
        "${AOSP_SYSTEM}/core/libutils/include"
        "${AOSP_SYSTEM}/core/libsystem/include")
# libtinyxml2 for the malloc_info() tests, with its Android flags.
set(TINYXML2 "${AOSP_EXTERNAL}/tinyxml2")
aosp_library(tinyxml2
    SRCS "${TINYXML2}/tinyxml2.cpp"
    FLAGS -Wall -Werror -Wno-implicit-fallthrough -DDEBUG -DANDROID_NDK
    INCLUDES "${TINYXML2}" "${LIBLOG}/include")
aosp_library(ziparchive
    SRCS "${ZIPARCHIVE}/zip_archive.cc"
        "${ZIPARCHIVE}/zip_archive_stream_entry.cc"
        "${ZIPARCHIVE}/zip_cd_entry_map.cc" "${ZIPARCHIVE}/zip_error.cpp"
    FLAGS -std=gnu++20 -DZLIB_CONST -DZIPARCHIVE_DISABLE_CALLBACK_API=0
        -DINCFS_SUPPORT_DISABLED=1
        -Wno-missing-field-initializers -Wconversion -Wno-sign-conversion
    INCLUDES "${ZIPARCHIVE}/include" "${ZIPARCHIVE}/incfs_support/include"
        "${LIBBASE}/include" "${LIBLOG}/include" "${ZLIB}")

# linker64: linker_bin_template and linker_binary_defaults of
# linker/Android.bp, with the linux_bionic choices (the debuggerd stub, no
# Rust).  It is a shared object that is linked statically (no -static: the
# FreeBSD clang driver then drops -shared).  The FreeBSD ABI note lets the
# kernel run it directly too.
add_executable(linker64
    "${LINKER}/arch/arm64/begin.S"
    "${LINKER}/arch/arm64/tlsdesc_resolver.S"
    "${LINKER}/arch/arm_neon/linker_gnu_hash_neon.cpp"
    "${LINKER}/dlfcn.cpp" "${LINKER}/linker.cpp" "${LINKER}/linker_auxv.cpp"
    "${LINKER}/linker_block_allocator.cpp" "${LINKER}/linker_dlwarning.cpp"
    "${LINKER}/linker_cfi.cpp" "${LINKER}/linker_config.cpp"
    "${LINKER}/linker_debug.cpp" "${LINKER}/linker_gdb_support.cpp"
    "${LINKER}/linker_globals.cpp" "${LINKER}/linker_libc_support.c"
    "${LINKER}/linker_libcxx_support.cpp" "${LINKER}/linker_namespaces.cpp"
    "${LINKER}/linker_logger.cpp" "${LINKER}/linker_mapped_file_fragment.cpp"
    "${LINKER}/linker_note_gnu_property.cpp" "${LINKER}/linker_phdr.cpp"
    "${LINKER}/linker_phdr_16kib_compat.cpp" "${LINKER}/linker_relocate.cpp"
    "${LINKER}/linker_sdk_versions.cpp" "${LINKER}/linker_soinfo.cpp"
    "${LINKER}/linker_transparent_hugepage_support.cpp"
    "${LINKER}/linker_tls.cpp" "${LINKER}/linker_utils.cpp"
    "${LINKER}/rt.cpp" "${LINKER}/linker_translate_path.cpp"
    "${LINKER}/linker_main.cpp" "${LINKER}/linker_memory.cpp"
    "${LINKER}/linker_debuggerd_stub.cpp"
    "${LIBC}/arch-common/freebsd/crtbrand_freebsd.S")
target_include_directories(linker64 SYSTEM BEFORE PRIVATE "${CXX_INCLUDE}")
target_include_directories(linker64 PRIVATE "${LIBC}/async_safe/include"
    "${LIBC}/system_properties/include" "${LIBBASE}/include"
    "${LIBLOG}/include" "${ZIPARCHIVE}/include")
target_compile_options(linker64 PRIVATE -fno-stack-protector
    -DZIPARCHIVE_DISABLE_CALLBACK_API=0
    -Wstrict-overflow=5 -fvisibility=hidden -Wextra -Wunused
    "$<$<COMPILE_LANGUAGE:CXX>:-std=gnu++20;${AOSP_CXX_FLAGS};-Wold-style-cast>")
set_source_files_properties("${LINKER}/linker_main.cpp" PROPERTIES
    COMPILE_OPTIONS -ffreestanding)
target_link_options(linker64 PRIVATE -nostdlib -shared
    -fuse-ld=lld -Wl,--no-undefined -Wl,-Bsymbolic -Wl,--exclude-libs,ALL
    -Wl,-soname,ld-android.so -Wl,--pack-dyn-relocs=relr -Wl,-e,_start
    -Wl,--gc-sections "-Wl,--version-script=${LINKER}/linker.generic.map")
target_link_libraries(linker64 PRIVATE c_nomalloc
    "${BIONIC_SYSROOT}/usr/lib/libc++.a" "${BIONIC_SYSROOT}/usr/lib/libc++abi.a"
    base ziparchive z log)
if(BUILTINS_LIB)
	target_link_libraries(linker64 PRIVATE "${BUILTINS_LIB}")
endif()

# abi_check: the probe gets the FreeBSD values from the FreeBSD sysroot,
# and abi_check.c must compile against the bionic-freebsd headers.
add_custom_command(OUTPUT "${GEN}/abi_check.c"
    COMMAND "${HOST_CC}" -Wall -o "${GEN}/abi_probe" "${PARITY}/abi_probe.c"
    COMMAND "${GEN}/abi_probe" > "${GEN}/abi_check.c"
    DEPENDS "${PARITY}/abi_probe.c"
    VERBATIM)
add_library(abi_check OBJECT "${GEN}/abi_check.c")

# Install the headers, libc.a and the crt objects as the bionic sysroot
# that the clang configuration points at:
#   cmake --install <build> --prefix /home/dev/build/sysroot-bionic-freebsd
install(DIRECTORY "${LIBC}/include/" DESTINATION usr/include
    PATTERN linux-compat EXCLUDE)
install(DIRECTORY "${LIBC}/include/linux-compat/" DESTINATION usr/include)
install(TARGETS c_static ARCHIVE DESTINATION usr/lib)
install(FILES "${GEN}/crtbegin_static.o" "${GEN}/crtbegin_dynamic.o"
    "${GEN}/crtbegin_so.o" "${GEN}/crtend.o" "${GEN}/crtend_so.o"
    DESTINATION usr/lib)

# Static test programs: bionic's startup, then main().
function(static_test name)
	add_executable(${name} ${name}.c)
	add_dependencies(${name} crt)
	target_link_options(${name} PRIVATE -static -nostdlib -fuse-ld=lld
	    -Wl,--gc-sections "${GEN}/crtbegin_static.o")
	target_link_libraries(${name} PRIVATE c_static "${GEN}/crtend.o")
	set_target_properties(${name} PROPERTIES
	    LINK_DEPENDS "${GEN}/crtbegin_static.o")
	if(BUILTINS_LIB)
		target_link_libraries(${name} PRIVATE "${BUILTINS_LIB}")
	endif()
endfunction()
static_test(hello_static)
static_test(ssp_test)
static_test(thread_test)
static_test(signal_test)

# A dynamic program: PT_INTERP /system/bin/linker64, DT_NEEDED libc.so.
function(dynamic_test name src)
	add_executable(${name} ${src})
	add_dependencies(${name} crt)
	target_link_options(${name} PRIVATE -nostdlib -fuse-ld=lld -pie
	    -Wl,--dynamic-linker=/system/bin/linker64 -Wl,--gc-sections
	    "${GEN}/crtbegin_dynamic.o")
	target_link_libraries(${name} PRIVATE c_shared "${GEN}/crtend.o")
	set_target_properties(${name} PROPERTIES SKIP_BUILD_RPATH ON
	    LINK_DEPENDS "${GEN}/crtbegin_dynamic.o")
	if(BUILTINS_LIB)
		target_link_libraries(${name} PRIVATE "${BUILTINS_LIB}")
	endif()
endfunction()
dynamic_test(hello_dynamic hello_static.c)
dynamic_test(thread_test_dynamic thread_test.c)

# The runtime APEX layout, for a chroot or a jail:
#   <build>/android-root/system/bin/hello_dynamic
add_custom_target(android_root ALL
    COMMAND "${CMAKE_COMMAND}" -E make_directory
        android-root/apex/com.android.runtime/bin
        android-root/apex/com.android.runtime/lib64/bionic
        android-root/system/bin android-root/system/lib64
    COMMAND "${CMAKE_COMMAND}" -E copy $<TARGET_FILE:linker64>
        android-root/apex/com.android.runtime/bin/linker64
    COMMAND "${CMAKE_COMMAND}" -E copy $<TARGET_FILE:c_shared>
        android-root/apex/com.android.runtime/lib64/bionic/libc.so
    COMMAND "${CMAKE_COMMAND}" -E copy $<TARGET_FILE:dl_shared>
        android-root/apex/com.android.runtime/lib64/bionic/libdl.so
    COMMAND "${CMAKE_COMMAND}" -E copy $<TARGET_FILE:dl_android>
        android-root/apex/com.android.runtime/lib64/bionic/libdl_android.so
    COMMAND "${CMAKE_COMMAND}" -E create_symlink
        /apex/com.android.runtime/bin/linker64 android-root/system/bin/linker64
    COMMAND "${CMAKE_COMMAND}" -E create_symlink
        /apex/com.android.runtime/lib64/bionic/libc.so
        android-root/system/lib64/libc.so
    COMMAND "${CMAKE_COMMAND}" -E create_symlink
        /apex/com.android.runtime/lib64/bionic/libdl.so
        android-root/system/lib64/libdl.so
    COMMAND "${CMAKE_COMMAND}" -E create_symlink
        /apex/com.android.runtime/lib64/bionic/libdl_android.so
        android-root/system/lib64/libdl_android.so
    COMMAND "${CMAKE_COMMAND}" -E copy $<TARGET_FILE:hello_dynamic>
        android-root/system/bin/hello_dynamic
    DEPENDS linker64 c_shared dl_shared dl_android hello_dynamic
    WORKING_DIRECTORY "${GEN}" VERBATIM)

enable_testing()
add_test(NAME parse_syscalls_master COMMAND sh
    "${PARITY}/test_parse_syscalls_master.sh")
set_tests_properties(parse_syscalls_master PROPERTIES SKIP_RETURN_CODE 77)
add_test(NAME syscall_numbers_current COMMAND sh -c
    "\"$0\" -f \"$1\" header \"$2\" | cmp - \"$3\""
    "${AWK}" "${PARITY}/parse_syscalls_master.awk"
    "${SYSCALLS_MASTER}" "${LIBC}/include/bits/freebsd/syscall_numbers.h")
add_test(NAME syscalls_freebsd_rows COMMAND "${AWK}" -f
    "${PARITY}/parse_syscalls_master.awk" check "${SYSCALLS_MASTER}"
    "${LIBC}/SYSCALLS.FREEBSD.TXT")
add_test(NAME hello_static COMMAND hello_static)
set_tests_properties(hello_static PROPERTIES
    PASS_REGULAR_EXPRESSION "^hello from bionic-freebsd")
# linker64 run as a program loads hello_dynamic and libc.so.  The test
# through PT_INTERP needs the android-root chroot or jail (root only).
# linker64 first warns that /linkerconfig/ld.config.txt does not exist.
add_test(NAME hello_dynamic_linker64 COMMAND linker64
    $<TARGET_FILE:hello_dynamic>)
set_tests_properties(hello_dynamic_linker64 PROPERTIES
    ENVIRONMENT "LD_LIBRARY_PATH=${GEN}"
    PASS_REGULAR_EXPRESSION "\nhello from bionic-freebsd")
add_test(NAME thread_dynamic_linker64 COMMAND linker64
    $<TARGET_FILE:thread_test_dynamic>)
set_tests_properties(thread_dynamic_linker64 PROPERTIES
    ENVIRONMENT "LD_LIBRARY_PATH=${GEN}" PASS_REGULAR_EXPRESSION "\nthreads ok")
# A zip with a duplicate entry comes first on LD_LIBRARY_PATH.
# libziparchive logs the entry with no tag, so liblog in linker64 takes
# getprogname() for the tag; with no program name, linker64 crashes
# before main().  The log goes to logd, not to stderr.  The zip does not
# open, and libc.so comes from the next directory.
add_custom_command(OUTPUT "${GEN}/dup_entry.zip"
    COMMAND bsdtar -c --format zip --options zip:compression=store
        -f "${GEN}/dup_entry.zip" -C "${CMAKE_CURRENT_SOURCE_DIR}"
        hello_static.c hello_static.c
    DEPENDS hello_static.c VERBATIM)
add_custom_target(dup_entry_zip ALL DEPENDS "${GEN}/dup_entry.zip")
add_test(NAME zip_dup_entry_linker64 COMMAND sh -c [=[
out=$(LD_LIBRARY_PATH="$1!/lib:$2" "$0" "$3" 2>&1)
rc=$?
echo "$out"
test $rc -eq 0 && echo "$out" | grep -q '^hello from bionic-freebsd'
]=] $<TARGET_FILE:linker64> "${GEN}/dup_entry.zip" "${GEN}"
    $<TARGET_FILE:hello_dynamic>)
add_test(NAME threads COMMAND thread_test)
set_tests_properties(threads PROPERTIES PASS_REGULAR_EXPRESSION "^threads ok")
add_test(NAME signals COMMAND signal_test)
set_tests_properties(signals PROPERTIES PASS_REGULAR_EXPRESSION "^signals ok")
add_test(NAME ssp_guard COMMAND ssp_test)
set_tests_properties(ssp_guard PROPERTIES
    PASS_REGULAR_EXPRESSION "^stack guard ok")
# The overflow must end with SIGABRT: the shell reports 128 + 6.
add_test(NAME ssp_trip COMMAND sh -c [=[
ulimit -c 0
out=$("$0" overflow 2>&1)
rc=$?
echo "$out"
test $rc -eq 134 && echo "$out" | grep -q 'stack corruption detected'
]=] "$<TARGET_FILE:ssp_test>")

# bionic-unit-tests-static, once googletest and gtest_extras are fetched,
# then the tests of libbase, liblog, libcutils and libutils.
if(EXISTS "${AOSP_EXTERNAL}/googletest/googletest/src/gtest-all.cc")
	include(tests.cmake)
	include(system-tests.cmake)
	include(boringssl.cmake)
	include(logd.cmake)
	include(selinux.cmake)
	include(toybox.cmake)
endif()
