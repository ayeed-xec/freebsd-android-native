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
# libselinux, libpcre2 and libpackagelistparser, as Android builds them,
# and a test of the project.  No libselinux file changes.  FreeBSD has no
# selinuxfs, so libselinux finds no SELinux mount and reports SELinux
# disabled, as on a Linux kernel without SELinux.
#
# The flags are those of the Android.bp files, and -DANDROID and -DNDEBUG
# of Soong's global flags; libselinux needs -DANDROID for its Android code.

set(SELINUX "${AOSP_EXTERNAL}/selinux/libselinux")
set(PCRE "${AOSP_EXTERNAL}/pcre")
if(NOT EXISTS "${SELINUX}/src/android/android_device.c" OR
    NOT EXISTS "${PCRE}/src/pcre2_compile.c")
	message(FATAL_ERROR "libselinux or pcre is missing; run aosp/fetch.sh "
	    "--project platform/external/selinux:libselinux "
	    "--project platform/external/pcre")
endif()

# libpcre2.so: pcre_defaults and libpcre2 of external/pcre/Android.bp.
# Its src/config.h has no SUPPORT_JIT, so it makes no executable memory.
set(PCRE2_SRCS auto_possess chartables chkdint compile compile_class config
    context convert dfa_match error extuni find_bracket jit_compile
    maketables match_data match newline ord2utf pattern_info script_run
    serialize string_utils study substitute substring tables ucd valid_utf
    xclass)
list(TRANSFORM PCRE2_SRCS PREPEND "${PCRE}/src/pcre2_")
list(TRANSFORM PCRE2_SRCS APPEND ".c")
system_library(pcre2_shared SONAME libpcre2.so SRCS ${PCRE2_SRCS})
set_target_properties(pcre2_shared PROPERTIES OUTPUT_NAME libpcre2)
target_include_directories(pcre2_shared PRIVATE "${PCRE}/include")
target_compile_options(pcre2_shared PRIVATE -DANDROID -DNDEBUG
    -DHAVE_CONFIG_H -Wall -Werror -DPCRE2_CODE_UNIT_WIDTH=8)

# libpackagelistparser.so of system/core/libpackagelistparser.  logd keeps
# its static library (logd.cmake).  libc++ is static in it and its symbols
# stay local, as in the other system libraries of tier 0.
system_library(packagelistparser_shared SONAME libpackagelistparser.so
    SRCS "${PKGLIST}/packagelistparser.cpp" LIBS log_shared ${LIBCXX_STATIC})
set_target_properties(packagelistparser_shared PROPERTIES
    OUTPUT_NAME libpackagelistparser)
target_include_directories(packagelistparser_shared SYSTEM BEFORE PRIVATE
    "${CXX_INCLUDE}")
target_include_directories(packagelistparser_shared PRIVATE
    "${PKGLIST}/include" ${SYSTEM_INCLUDES})
target_compile_options(packagelistparser_shared PRIVATE -std=gnu++20
    -DANDROID -DNDEBUG ${AOSP_CXX_FLAGS})
target_link_options(packagelistparser_shared PRIVATE
    -Wl,--exclude-libs,ALL)

# libselinux.so: libselinux_defaults and the android target of
# libselinux/Android.bp, with its version script exported.map.txt.  Soong
# ends the flags of external/ code with -Wno-unused
# (noOverrideExternalGlobalCflags); regex.c sets a variable that only an
# assert() reads.  -Wno-undef stops the -Wundef of our clang configuration
# (android_seapp.c and android_device.c test DEBUG with #if).
set(SELINUX_SRCS android/android.c android/android_seapp.c avc.c
    avc_internal.c avc_sidtab.c booleans.c callbacks.c canonicalize_context.c
    checkAccess.c check_context.c compute_av.c compute_create.c
    compute_member.c context.c deny_unknown.c disable.c enabled.c
    fgetfilecon.c freecon.c fsetfilecon.c get_initial_context.c getenforce.c
    getfilecon.c getpeercon.c hashtab.c init.c label.c
    label_backends_android.c label_file.c label_support.c lgetfilecon.c
    load_policy.c lsetfilecon.c mapping.c matchpathcon.c policyvers.c
    procattr.c regex.c reject_unknown.c selinux_internal.c sestatus.c
    setenforce.c setfilecon.c setrans_client.c sha1.c stringrep.c
    android/android_device.c)
list(TRANSFORM SELINUX_SRCS PREPEND "${SELINUX}/src/")
system_library(selinux_shared SONAME libselinux.so
    MAP "${SELINUX}/exported.map.txt" SRCS ${SELINUX_SRCS}
    LIBS pcre2_shared log_shared packagelistparser_shared)
set_target_properties(selinux_shared PROPERTIES OUTPUT_NAME libselinux)
target_include_directories(selinux_shared PRIVATE "${SELINUX}/include"
    "${SELINUX}/src" "${PCRE}/include" "${PKGLIST}/include"
    "${LIBBASE}/include" "${AOSP_SYSTEM}/core/libcutils/include"
    "${LIBLOG}/include")
target_compile_options(selinux_shared PRIVATE -DANDROID -DNDEBUG
    -DNO_PERSISTENTLY_STORED_PATTERNS -DDISABLE_SETRANS -DDISABLE_BOOL
    -D_GNU_SOURCE -DNO_MEDIA_BACKEND -DNO_X_BACKEND -DNO_DB_BACKEND -Wall
    -Werror -Wno-error=missing-noreturn -Wno-error=unused-function
    -Wno-error=unused-variable -DUSE_PCRE2 -DAUDITD_LOG_TAG=1003
    -DHAVE_STRLCPY -DHAVE_REALLOCARRAY -Wno-unused -Wno-undef)

# libselinux_freebsd_test: the disabled state of libselinux in the jail
# (docs/specs/libselinux.md, section 8), with a small file_contexts file
# next to the program.
system_test(libselinux_freebsd_test
    SRCS "${CMAKE_CURRENT_SOURCE_DIR}/libselinux_freebsd_test.cpp"
    LIBS gtest_main selinux_shared
    INCLUDES "${SELINUX}/include")
add_test(NAME libselinux_freebsd_test COMMAND ${RUN_SUITE}
    -j "${GEN}/bionic-tests-jail.conf"
    -d "${CMAKE_CURRENT_SOURCE_DIR}/libselinux_freebsd_test.file_contexts"
    "${CMAKE_CURRENT_SOURCE_DIR}/libselinux_freebsd_test.excluded"
    "$<TARGET_FILE:linker64>" "$<TARGET_FILE:libselinux_freebsd_test>")
set_tests_properties(libselinux_freebsd_test PROPERTIES
    ENVIRONMENT "LD_LIBRARY_PATH=${GEN};${RUN_SUITE_PATH}")
