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
# Initial cache for libc++ and libc++abi on bionic-freebsd (ADR 0002,
# decision 1.7): LLVM's runtimes build at the tag of our clang, with
# aosp/patches/llvm-project applied.  Tier 0 builds the static variant
# without exceptions that linker64 needs (libc++_static_noexcept).
#
#   cmake -G Ninja -C aosp/cmake/tier0/libcxx.cmake \
#       -S /home/dev/src/llvm-project/runtimes -B /home/dev/build/libcxx \
#       -DCMAKE_TOOLCHAIN_FILE=config/toolchain/aarch64-freebsd-android37.cmake
#   ninja -C /home/dev/build/libcxx install-cxx install-cxxabi
#
# The headers and libraries go to the bionic sysroot; the bionic headers
# must be there first (cmake --install of aosp/cmake/tier0/bionic).

set(CMAKE_BUILD_TYPE Release CACHE STRING "")
set(CMAKE_INSTALL_PREFIX /home/dev/build/sysroot-bionic-freebsd/usr
    CACHE PATH "")
set(CMAKE_POSITION_INDEPENDENT_CODE ON CACHE BOOL "")
set(LLVM_ENABLE_RUNTIMES "libcxx;libcxxabi" CACHE STRING "")
set(LLVM_INCLUDE_TESTS OFF CACHE BOOL "")
set(LLVM_INCLUDE_DOCS OFF CACHE BOOL "")

# bionic has the pthread and rt functions in libc: no -lpthread, no -lrt.
set(LIBCXX_HAS_PTHREAD_LIB OFF CACHE BOOL "")
set(LIBCXX_HAS_RT_LIB OFF CACHE BOOL "")
set(LIBCXXABI_HAS_PTHREAD_LIB OFF CACHE BOOL "")

set(LIBCXX_ENABLE_SHARED OFF CACHE BOOL "")
set(LIBCXX_ENABLE_EXCEPTIONS OFF CACHE BOOL "")
set(LIBCXX_ENABLE_TIME_ZONE_DATABASE OFF CACHE BOOL "")
set(LIBCXX_CXX_ABI libcxxabi CACHE STRING "")
set(LIBCXX_USE_COMPILER_RT ON CACHE BOOL "")
set(LIBCXX_INCLUDE_TESTS OFF CACHE BOOL "")
set(LIBCXX_INCLUDE_BENCHMARKS OFF CACHE BOOL "")

set(LIBCXXABI_ENABLE_SHARED OFF CACHE BOOL "")
set(LIBCXXABI_ENABLE_EXCEPTIONS OFF CACHE BOOL "")
set(LIBCXXABI_USE_LLVM_UNWINDER OFF CACHE BOOL "")
set(LIBCXXABI_USE_COMPILER_RT ON CACHE BOOL "")
set(LIBCXXABI_INCLUDE_TESTS OFF CACHE BOOL "")
