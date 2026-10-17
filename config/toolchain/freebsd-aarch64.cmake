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
# CMake toolchain for host tools and FreeBSD-side probes on FreeBSD/aarch64
# (plan §9.2, P1).  These programs use FreeBSD libc and the base compiler.
# __ANDROID__ and __BIONIC__ are not defined (ADR 0002, decision 2).  Android
# code uses aarch64-unknown-freebsd15-android37.cfg and ports clang 22.
#
#   cmake -DCMAKE_TOOLCHAIN_FILE=<this file> [-DHOST_CC=clang22 ...]

set(HOST_CC cc CACHE STRING "C compiler for host tools")
set(HOST_CXX c++ CACHE STRING "C++ compiler for host tools")

set(CMAKE_C_COMPILER ${HOST_CC})
set(CMAKE_CXX_COMPILER ${HOST_CXX})
set(CMAKE_C_COMPILER_TARGET aarch64-unknown-freebsd15)
set(CMAKE_CXX_COMPILER_TARGET aarch64-unknown-freebsd15)

# Ports libraries (libepoll-shim, libfmt, googletest) are in /usr/local.
list(APPEND CMAKE_PREFIX_PATH /usr/local)
