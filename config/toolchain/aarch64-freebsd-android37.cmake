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
# CMake toolchain for Android code on FreeBSD/aarch64 (ADR 0002, decision 2):
# ports clang 22 with aarch64-unknown-freebsd15-android37.cfg.  Host tools
# use freebsd-aarch64.cmake instead.
#
#   cmake -DCMAKE_TOOLCHAIN_FILE=<this file> [-DANDROID_CLANG=clang22 ...]

set(ANDROID_CLANG clang22 CACHE STRING "Compiler for Android code")
set(ANDROID_CLANGXX clang++22 CACHE STRING "C++ compiler for Android code")
set(ANDROID_CLANG_CFG
    "${CMAKE_CURRENT_LIST_DIR}/aarch64-unknown-freebsd15-android37.cfg"
    CACHE FILEPATH "clang configuration file for Android code")

set(CMAKE_C_COMPILER ${ANDROID_CLANG})
set(CMAKE_CXX_COMPILER ${ANDROID_CLANGXX})
set(CMAKE_ASM_COMPILER ${ANDROID_CLANG})
set(CMAKE_C_FLAGS_INIT "--config=${ANDROID_CLANG_CFG}")
set(CMAKE_ASM_FLAGS_INIT "--config=${ANDROID_CLANG_CFG}")
# clang defines _GNU_SOURCE for C++ on Linux targets, Android included, but
# not on FreeBSD targets.  Android C++ code needs it.
set(CMAKE_CXX_FLAGS_INIT "--config=${ANDROID_CLANG_CFG} -D_GNU_SOURCE")

# There is no bionic libc to link against while it is built: test the
# compiler with a static library, not with a program.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
