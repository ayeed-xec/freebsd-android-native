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
# bionic-unit-tests-static and bionic-unit-tests with the pthread, signal,
# stdio, string, stack_protector, time and unistd tests.  Flags follow
# bionic_tests_defaults in bionic's tests/Android.bp.  The dynamic suite
# links against libc.so and runs under linker64.  Run them in the dev VM
# with
#
#   ctest --test-dir <build> -R bionic_unit_tests -V
#
# which skips the tests listed in the .excluded file of each suite.  The
# time tests read tzdata from /apex/com.android.tzdata/etc/tz/tzdata.

set(GTEST "${AOSP_EXTERNAL}/googletest/googletest")
set(GTEST_ISOLATED "${AOSP_SYSTEM}/testing/gtest_extras/gtest_isolated")
set(BIONIC_TESTS "${BIONIC_SRC}/tests")

aosp_library(gtest
    SRCS "${GTEST}/src/gtest-all.cc"
    FLAGS -std=gnu++20 -Wno-unused-private-field
        # GTEST_CAN_STREAM_RESULTS_ is 0: that removes getaddrinfo,
        # freeaddrinfo and gai_strerror.  -D does not work: gtest-port.h
        # sets the macro for FreeBSD.
        -include "${CMAKE_CURRENT_SOURCE_DIR}/gtest_no_stream_results.h"
    INCLUDES "${GTEST}" "${GTEST}/include")
aosp_library(gtest_isolated
    SRCS "${GTEST_ISOLATED}/Color.cpp" "${GTEST_ISOLATED}/Isolate.cpp"
        "${GTEST_ISOLATED}/IsolateMain.cpp" "${GTEST_ISOLATED}/NanoTime.cpp"
        "${GTEST_ISOLATED}/Options.cpp" "${GTEST_ISOLATED}/Test.cpp"
    FLAGS -std=gnu++20 -Wall -Werror
        # Isolate.cpp only gets <sys/wait.h> through googletest's Linux
        # branch.
        -include sys/wait.h
    INCLUDES "${GTEST_ISOLATED}/include" "${GTEST}/include"
        "${LIBLOG}/include")

# Just enough libm for the tests: the arm-optimized-routines math that
# libarm-optimized-routines-math builds, nan() and nextafter().
set(AOR_MATH "${AOSP_EXTERNAL}/arm-optimized-routines/math")
set(AOR_MATH_SRCS cosf exp exp2 exp2f exp2f_data exp_data expf log log2
    log2_data log2f log2f_data log_data logf logf_data math_err math_errf
    pow pow_log_data powf powf_log2_data sincosf sincosf_data sinf)
list(TRANSFORM AOR_MATH_SRCS PREPEND "${AOR_MATH}/")
list(TRANSFORM AOR_MATH_SRCS APPEND ".c")
set(MSUN_SRCS s_nan s_nextafter)
list(TRANSFORM MSUN_SRCS PREPEND
    "${BIONIC_SRC}/libm/upstream-freebsd/lib/msun/src/")
list(TRANSFORM MSUN_SRCS APPEND ".c")
add_library(m_static STATIC ${AOR_MATH_SRCS} ${MSUN_SRCS})
set_source_files_properties(${MSUN_SRCS} PROPERTIES
    COMPILE_OPTIONS "-include;freebsd-compat.h;-fno-builtin")
set_target_properties(m_static PROPERTIES OUTPUT_NAME m)
target_include_directories(m_static PRIVATE "${AOR_MATH}/include"
    "${BIONIC_SRC}/libm" "${BIONIC_SRC}/libm/upstream-freebsd/android/include"
    "${BIONIC_SRC}/libm/upstream-freebsd/lib/msun/src" "${LIBC}")
target_compile_options(m_static PRIVATE -Wno-undef -Wno-unused-parameter -O2
    -ffp-contract=fast -fno-math-errno -D__BIONIC_LP32_USE_LONG_DOUBLE
    -DFLT_EVAL_METHOD=0 -DWANT_ERRNO=0 -DWANT_VMATH=0 -DWANT_SIMD_TESTS=0
    -DWANT_EXP10_TESTS=0 -DWANT_MOPS=1 -DHAVE_FAST_FMA=1)

set(BIONIC_TEST_SRCS gtest_globals.cpp gtest_main.cpp utils.cpp
    buffer_tests.cpp stack_protector_test_helper.cpp
    pthread_test.cpp signal_test.cpp stdio_test.cpp string_test.cpp
    stack_protector_test.cpp time_test.cpp unistd_test.cpp)
list(TRANSFORM BIONIC_TEST_SRCS PREPEND "${BIONIC_TESTS}/")

# The exec tests run echo, printenv and sh from BIN_DIR.  FreeBSD keeps
# printenv in /usr/bin, so link all three into one directory.
set(TEST_BIN "${CMAKE_CURRENT_BINARY_DIR}/test-bin")
file(MAKE_DIRECTORY "${TEST_BIN}")
foreach(prog /bin/echo /bin/sh /usr/bin/printenv)
	get_filename_component(name "${prog}" NAME)
	file(CREATE_LINK "${prog}" "${TEST_BIN}/${name}" SYMBOLIC)
endforeach()

# Both suites link the same objects.
add_library(bionic_test_objs OBJECT ${BIONIC_TEST_SRCS})
target_include_directories(bionic_test_objs SYSTEM BEFORE PRIVATE
    "${CXX_INCLUDE}")
target_include_directories(bionic_test_objs PRIVATE "${LIBC}"
    "${LIBC}/platform" "${BIONIC_TESTS}" "${GTEST}/include"
    "${GTEST_ISOLATED}/include" "${LIBBASE}/include" "${LIBLOG}/include"
    "${AOSP_SYSTEM}/core/libcutils/include")
target_compile_definitions(bionic_test_objs PRIVATE "BIN_DIR=\"${TEST_BIN}/\"")
# -Wextra goes first so AOSP's -Wno-* flags still win.  clang 22 warns
# about function type casts where AOSP's clang does not.  mode_t is 16 bits
# on FreeBSD, so st_mode & 0777 promotes to int and trips -Wsign-compare
# against the tests' unsigned constants.
target_compile_options(bionic_test_objs PRIVATE -std=gnu++20
    -Wextra ${AOSP_CXX_FLAGS} -fstack-protector-all -Wunused -fno-builtin
    -Wno-deprecated-declarations -Wno-invalid-offsetof
    -Wno-reorder-init-list -Wno-cast-function-type-mismatch -Wno-sign-compare
    -fsanitize=shadow-call-stack)
set(BIONIC_TEST_LIBS -Wl,--start-group gtest_isolated gtest base log m_static
    "${BIONIC_SYSROOT}/usr/lib/libc++.a" "${BIONIC_SYSROOT}/usr/lib/libc++abi.a"
    -Wl,--end-group)

add_executable(bionic-unit-tests-static $<TARGET_OBJECTS:bionic_test_objs>)
add_dependencies(bionic-unit-tests-static crt)
target_link_options(bionic-unit-tests-static PRIVATE -static -nostdlib
    -fuse-ld=lld -Wl,--gc-sections "${GEN}/crtbegin_static.o")
target_link_libraries(bionic-unit-tests-static PRIVATE ${BIONIC_TEST_LIBS}
    c_static "${GEN}/crtend.o")
set_target_properties(bionic-unit-tests-static PROPERTIES
    LINK_DEPENDS "${GEN}/crtbegin_static.o")

# As in bionic_unit_tests_defaults: PIE, --export-dynamic, libc++ static.
add_executable(bionic-unit-tests $<TARGET_OBJECTS:bionic_test_objs>)
add_dependencies(bionic-unit-tests crt)
target_link_options(bionic-unit-tests PRIVATE -nostdlib -fuse-ld=lld -pie
    -Wl,--dynamic-linker=/system/bin/linker64 -Wl,--export-dynamic
    -Wl,--gc-sections "${GEN}/crtbegin_dynamic.o")
target_link_libraries(bionic-unit-tests PRIVATE ${BIONIC_TEST_LIBS}
    c_shared dl_shared "${GEN}/crtend.o")
set_target_properties(bionic-unit-tests PROPERTIES SKIP_BUILD_RPATH ON
    LINK_DEPENDS "${GEN}/crtbegin_dynamic.o")

if(BUILTINS_LIB)
	target_link_libraries(bionic-unit-tests-static PRIVATE "${BUILTINS_LIB}")
	target_link_libraries(bionic-unit-tests PRIVATE "${BUILTINS_LIB}")
endif()

# Run each test in its own process, 6 at a time, which is what the
# isolated runner of gtest_extras would do.  That runner lists the tests
# through popen(), which runs "sh -c -- cmd", and FreeBSD's /bin/sh takes
# the "--" as the command.  Android's own shell does not have this problem.
# The arguments after the exclusion list are the command that runs the
# suite.
function(bionic_gtest_suite name excluded)
	add_test(NAME ${name} COMMAND sh -c [=[
excluded=$0
tmp=$(mktemp -d)
awk '!/^#/ && NF { print $1 }' "$excluded" > "$tmp/excluded"
"$@" --no_isolate --gtest_list_tests |
    awk '/^[^ ]/ { s = $1 } /^  / { print s $1 }' |
    grep -v DISABLED_ | grep -vxFf "$tmp/excluded" > "$tmp/tests"
xargs -P 6 -I % sh -c 't=$0 tmp=$1; shift; cd /tmp && TMPDIR=/tmp \
    timeout 120 "$@" --no_isolate "--gtest_filter=$t" > "$tmp/$t.log" 2>&1 ||
    echo "$t"' % "$tmp" "$@" < "$tmp/tests" > "$tmp/failed"
echo "$(wc -l < "$tmp/tests") tests run, $(wc -l < "$tmp/failed") failed"
for t in $(cat "$tmp/failed"); do
	echo "=== $t"
	tail -20 "$tmp/$t.log"
done
test ! -s "$tmp/failed"
rc=$?
rm -rf "$tmp"
exit $rc
]=] "${CMAKE_CURRENT_SOURCE_DIR}/${excluded}" ${ARGN})
endfunction()
bionic_gtest_suite(bionic_unit_tests_static bionic-unit-tests-static.excluded
    "$<TARGET_FILE:bionic-unit-tests-static>")
bionic_gtest_suite(bionic_unit_tests bionic-unit-tests.excluded
    "$<TARGET_FILE:linker64>" "$<TARGET_FILE:bionic-unit-tests>")
set_tests_properties(bionic_unit_tests PROPERTIES
    ENVIRONMENT "LD_LIBRARY_PATH=${GEN}")
