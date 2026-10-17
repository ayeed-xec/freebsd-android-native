# Copyright (c) 2026 <copyright holder>
#
# SPDX-License-Identifier: BSD-2-Clause
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
