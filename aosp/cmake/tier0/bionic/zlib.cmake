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
# zlib: the libz module of external/zlib/Android.bp.  The flags are
# cflags_shared and cflags_arm64 of libz_defaults, and -DARMV8_OS_LINUX of
# its linux_arm64 target, which Soong applies to Android too; -DANDROID and
# -DNDEBUG are Soong's flags for all device code.  -Wno-undef stops the
# -Wundef of our clang configuration, which AOSP's clang does not have
# (crc32.c tests ARMCRC32_CANONICAL_ZLIB with #if).  cpu_features.c reads
# AT_HWCAP with getauxval() and tests HWCAP_CRC32 and HWCAP_PMULL of
# <asm/hwcap.h>, which bionic-freebsd gives from the FreeBSD kernel ABI.
#
# The sources are compiled once.  linker64, libziparchive and the bionic
# tests link the static variant z, as their Android.bp files say;
# android-root.cmake links libz.so from the same objects.

set(ZLIB "${AOSP_EXTERNAL}/zlib")
if(NOT EXISTS "${ZLIB}/cpu_features.c")
	message(FATAL_ERROR "${ZLIB} is missing; run aosp/fetch.sh "
	    "--project platform/external/zlib")
endif()
set(ZLIB_FLAGS -DANDROID -DNDEBUG -DHAVE_HIDDEN -DZLIB_CONST
    -DCHROMIUM_ZLIB_NO_CASTAGNOLI -O3 -Wall -Werror
    -Wno-deprecated-non-prototype -Wno-unused -Wno-unused-parameter
    -DADLER32_SIMD_NEON -DCRC32_ARMV8_CRC32 -DDEFLATE_CHUNK_WRITE_64LE
    -DINFLATE_CHUNK_READ_64LE -DARMV8_OS_LINUX -Wno-undef)
set(ZLIB_SRCS adler32 adler32_simd compress cpu_features crc32 crc32_simd
    crc_folding deflate gzclose gzlib gzread gzwrite infback inffast inflate
    inftrees trees uncompr zutil)
list(TRANSFORM ZLIB_SRCS PREPEND "${ZLIB}/")
list(TRANSFORM ZLIB_SRCS APPEND ".c")
add_library(zlib_objects OBJECT ${ZLIB_SRCS})
target_include_directories(zlib_objects PRIVATE "${ZLIB}")
target_compile_options(zlib_objects PRIVATE ${ZLIB_FLAGS})
add_library(z STATIC $<TARGET_OBJECTS:zlib_objects>)
