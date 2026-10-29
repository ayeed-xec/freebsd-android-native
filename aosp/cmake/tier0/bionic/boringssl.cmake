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
# BoringSSL: libcrypto of external/boringssl/Android.bp in Android's FIPS
# configuration, and its tests.  The source lists are the ones of the
# generated android-sources.cmake, which has the lists of sources.bp.
#
# The FIPS module (bcm_object) is bcm.cc, compiled with one code and one
# read-only data section and linked by itself with fips_shared.lds, which
# marks its bounds.  libcrypto.so links the module and the other sources.
# inject_hash then writes the HMAC-SHA256 of the module into the library,
# as Soong's inject_bssl_hash does with bssl_inject_hash.  At load time the
# module computes the same value, aborts if the two differ, and runs its
# self tests.  libcrypto_static is the same code without FIPS, for
# boringssl_crypto_test.
#
# The flags are boringssl_flags_common, boringssl_flags and
# boringssl_defaults, and -DANDROID, -DNDEBUG and -fno-strict-aliasing of
# Soong's global flags (cc/config/global.go); BoringSSL's
# CompilerTest.NoStrictAliasing asserts the last one.  On this target
# BoringSSL takes its FreeBSD code: the CPU features from the ID registers,
# which the kernel traps, getentropy() and pthread_atfork().

set(BORINGSSL "${AOSP_EXTERNAL}/boringssl")
if(NOT EXISTS "${BORINGSSL}/src/crypto/fipsmodule/bcm.cc")
	message(FATAL_ERROR "${BORINGSSL} is missing; run aosp/fetch.sh "
	    "--project platform/external/boringssl")
endif()
set(BORINGSSL_ROOT "${BORINGSSL}/")
include("${BORINGSSL}/android-sources.cmake")
set(BCM_SRC "${BORINGSSL}/src/crypto/fipsmodule/bcm.cc")
set(LIBCRYPTO_SRCS ${crypto_sources})
list(REMOVE_ITEM LIBCRYPTO_SRCS "${BCM_SRC}")
set(BORINGSSL_FLAGS -DANDROID -DNDEBUG -fno-strict-aliasing
    -fvisibility=hidden -DBORINGSSL_SHARED_LIBRARY -DOPENSSL_SMALL -Werror
    -Wno-unused-parameter -DBORINGSSL_ANDROID_SYSTEM
    "$<$<COMPILE_LANGUAGE:CXX>:-std=gnu++20;-Wall;${AOSP_CXX_FLAGS}>")

function(boringssl_objects name)
	cmake_parse_arguments(B "" "" "SRCS;FLAGS" ${ARGN})
	add_library(${name} OBJECT ${B_SRCS})
	target_include_directories(${name} SYSTEM BEFORE PRIVATE
	    "${CXX_INCLUDE}")
	target_include_directories(${name} PRIVATE "${BORINGSSL}/src/include")
	target_compile_options(${name} PRIVATE ${BORINGSSL_FLAGS}
	    -DBORINGSSL_IMPLEMENTATION ${B_FLAGS})
endfunction()

# bcm_object.  Its flags come after the global -ffunction-sections and
# -fdata-sections, so they win.
boringssl_objects(boringssl_bcm SRCS "${BCM_SRC}"
    FLAGS -DBORINGSSL_FIPS -fPIC -fno-data-sections -fno-function-sections)
set(FIPS_LDS "${BORINGSSL}/src/crypto/fipsmodule/fips_shared.lds")
add_custom_command(OUTPUT "${GEN}/bcm_object.o"
    COMMAND "${CMAKE_CXX_COMPILER}" "--config=${ANDROID_CLANG_CFG}"
        -nostdlib -fuse-ld=lld -Wl,-r "-Wl,-T,${FIPS_LDS}"
        -o "${GEN}/bcm_object.o" "$<TARGET_OBJECTS:boringssl_bcm>"
    DEPENDS "$<TARGET_OBJECTS:boringssl_bcm>" "${FIPS_LDS}"
    COMMAND_EXPAND_LISTS VERBATIM)
set_source_files_properties("${GEN}/bcm_object.o" PROPERTIES
    EXTERNAL_OBJECT ON GENERATED ON)

# libcrypto.so, linked with -Bsymbolic as on Android.  libc++ is static in
# it and its symbols stay local.
boringssl_objects(boringssl_crypto SRCS ${LIBCRYPTO_SRCS} ${crypto_sources_asm}
    FLAGS -DBORINGSSL_FIPS)
system_library(crypto_shared SONAME libcrypto.so
    SRCS "${GEN}/bcm_object.o" $<TARGET_OBJECTS:boringssl_crypto>
    LIBS ${LIBCXX_STATIC})
set_target_properties(crypto_shared PROPERTIES
    OUTPUT_NAME libcrypto.unhashed)
target_link_options(crypto_shared PRIVATE -Wl,-Bsymbolic
    -Wl,--exclude-libs,ALL)

# The hash step, with our host tool tools/fips/inject_hash.c.  The file
# with the hash is <build>/libcrypto.so; android-root.cmake installs it.
add_custom_command(OUTPUT "${GEN}/inject_hash"
    COMMAND "${HOST_CC}" -Wall -o "${GEN}/inject_hash"
        "${PROJECT_ROOT}/tools/fips/inject_hash.c" -lelf -lmd
    DEPENDS "${PROJECT_ROOT}/tools/fips/inject_hash.c" VERBATIM)
add_custom_command(OUTPUT "${GEN}/libcrypto.so"
    COMMAND "${GEN}/inject_hash" -v -o "${GEN}/libcrypto.so"
        "$<TARGET_FILE:crypto_shared>"
    DEPENDS crypto_shared "${GEN}/inject_hash" VERBATIM)
add_custom_target(crypto_hashed ALL DEPENDS "${GEN}/libcrypto.so")

# libcrypto_static: the module and the other sources without FIPS.
boringssl_objects(boringssl_crypto_static
    SRCS ${crypto_sources} ${crypto_sources_asm})
add_library(crypto_static STATIC $<TARGET_OBJECTS:boringssl_crypto_static>)

# test_fips: the FIPS state of libcrypto.so.  "Module is in FIPS mode" needs
# the integrity check and the power-on self tests at load time.  On this
# BoringSSL stream FIPS_version() is 0 (self_check/fips.cc.inc), so the
# program then prints "No module version set" and aborts, as on Android.
# The test checks both lines and the abort.
system_program(test_fips SRCS "${BORINGSSL}/src/util/fipstools/test_fips.cc"
    LIBS crypto_shared ${LIBCXX_STATIC})
add_dependencies(test_fips crypto_hashed)
target_include_directories(test_fips SYSTEM BEFORE PRIVATE "${CXX_INCLUDE}")
target_include_directories(test_fips PRIVATE "${BORINGSSL}/src/include")
target_compile_options(test_fips PRIVATE ${BORINGSSL_FLAGS} -DBORINGSSL_FIPS)
add_test(NAME test_fips COMMAND sh -c [=[
ulimit -c 0
out=$(sh "$0" "$1" "$2" 2>&1)
rc=$?
echo "$out"
test $rc -eq 77 && exit 77
test $rc -eq 134 &&
    echo "$out" | grep -qx 'Module is in FIPS mode' &&
    echo "$out" | grep -qx 'No module version set'
]=] "${CMAKE_CURRENT_SOURCE_DIR}/run-in-jail.sh"
    "${GEN}/bionic-tests-jail.conf" "$<TARGET_FILE:test_fips>")
set_tests_properties(test_fips PROPERTIES SKIP_RETURN_CODE 77)

# boringssl_crypto_test, with boringssl_test_support in it
# (whole_static_libs), libcrypto_static and gmock.  Its data files go to
# /data/local/tmp/boringssl_crypto_test/src in the jail, and
# BORINGSSL_TEST_DATA_ROOT names that directory, as CryptoNativeTests.xml
# does on a device.  Android runs it in one process and not as root.
system_test(boringssl_crypto_test
    SRCS ${crypto_test_sources} ${test_support_sources}
    LIBS crypto_static gmock
    FLAGS ${BORINGSSL_FLAGS}
    INCLUDES "${BORINGSSL}/src/include" "${GMOCK}/include")
set(BORINGSSL_DATA "${GEN}/boringssl-data")
foreach(f ${crypto_test_data})
	file(RELATIVE_PATH rel "${BORINGSSL}" "${f}")
	configure_file("${f}" "${BORINGSSL_DATA}/${rel}" COPYONLY)
endforeach()
add_test(NAME boringssl_crypto_test COMMAND ${RUN_SUITE}
    -j "${GEN}/bionic-tests-jail.conf" -d "${BORINGSSL_DATA}/src" -s
    "${CMAKE_CURRENT_SOURCE_DIR}/boringssl_crypto_test.excluded"
    "$<TARGET_FILE:linker64>" "$<TARGET_FILE:boringssl_crypto_test>")
set(BORINGSSL_TEST_ENV "LD_LIBRARY_PATH=${GEN}" "${RUN_SUITE_PATH}"
    "BORINGSSL_TEST_DATA_ROOT=/data/local/tmp/boringssl_crypto_test/src")
set_tests_properties(boringssl_crypto_test PROPERTIES ENVIRONMENT
    "${BORINGSSL_TEST_ENV}")
