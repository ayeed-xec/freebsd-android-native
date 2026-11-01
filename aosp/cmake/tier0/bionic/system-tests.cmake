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
# libbase_test, liblog-unit-tests, libcutils_test and libutils_test, with
# the device flavour of libcutils, libutils and libvndksupport.  Sources and
# flags follow the Android.bp files of system/libbase,
# system/logging/liblog/tests, system/core/libcutils, system/core/libutils
# and system/core/libvndksupport.  Each suite is a PIE with PT_INTERP
# /system/bin/linker64 that links the libraries and libc++ statically, and
# runs in the bionic_tests jail, as bionic-unit-tests does:
#
#   ctest --test-dir <build> -R '^lib(base|log|cutils|utils)' -V
#
# The .excluded file of each suite names the tests that the run leaves
# out.  It also names the tests of the files that are not built yet:
# CallStack_test.cpp needs libunwindstack and sched_policy_test.cpp needs
# libprocessgroup.  The libcutils files that include <linux/ioprio.h> or
# <linux/netlink.h>, and their tests, wait for those linux-compat headers
# of bionic-freebsd.

set(GMOCK "${AOSP_EXTERNAL}/googletest/googlemock")
set(LIBCUTILS "${AOSP_SYSTEM}/core/libcutils")
set(LIBUTILS "${AOSP_SYSTEM}/core/libutils")
set(LIBVNDKSUPPORT "${AOSP_SYSTEM}/core/libvndksupport")
if(NOT EXISTS "${GMOCK}/src/gmock-all.cc" OR
    NOT EXISTS "${LIBVNDKSUPPORT}/linker.cpp")
	message(FATAL_ERROR "googlemock or libvndksupport is missing; add "
	    "them to the sparse checkouts of external/googletest and "
	    "system/core")
endif()
# libcutils_headers and libutils_headers, and system/core/include, which
# is one of Soong's global include directories.
set(SYSTEM_INCLUDES "${LIBBASE}/include" "${FMTLIB}/include"
    "${LIBLOG}/include" "${LIBCUTILS}/include"
    "${AOSP_SYSTEM}/core/libprocessgroup/include"
    "${AOSP_SYSTEM}/core/libsystem/include" "${AOSP_SYSTEM}/core/include")
set(LIBUTILS_INCLUDES "${LIBUTILS}/include" "${LIBUTILS}/binder/include"
    ${SYSTEM_INCLUDES})

# gmock_flags and libgmock.  The libc++ of the bionic sysroot has no
# exceptions (libcxx.cmake), so gmock is built without the -fexceptions of
# its module; no test here uses testing::Throw.
aosp_library(gmock
    SRCS "${GMOCK}/src/gmock-all.cc"
    FLAGS -Wall -Werror -Wno-missing-field-initializers -Wno-sign-compare
        -Wno-unused-parameter
    INCLUDES "${GMOCK}" "${GMOCK}/include" "${GTEST}/include"
    SOONG EXTERNAL RTTI)
# libgtest_defaults and libgtest_main.
aosp_library(gtest_main
    SRCS "${GTEST}/src/gtest_main.cc"
    FLAGS -Wall -Werror -Wno-unused-private-field
    INCLUDES "${GTEST}/include"
    SOONG EXTERNAL)
aosp_library(gtest_isolated_main
    SRCS "${GTEST_ISOLATED}/Main.cpp"
    FLAGS -Wall -Werror -Wextra
    INCLUDES "${GTEST_ISOLATED}/include" "${GTEST}/include")

# libcutils_sockets and libcutils, the android target, without
# iosched_policy.cpp and uevent.cpp, which need linux-compat headers that
# bionic-freebsd does not have yet.  ashmem-dev.cpp uses memfd, as
# sys.use_memfd=true in the build.prop of the jail tells it.  libcutils
# has libcutils_sockets in it; only libcutils adds -Wall and -Wextra to
# the flags of libcutils_defaults.
set(LIBCUTILS_SOCKETS_SRCS sockets.cpp android_get_control_file.cpp
    socket_inaddr_any_server_unix.cpp socket_local_client_unix.cpp
    socket_local_server_unix.cpp socket_network_client_unix.cpp
    sockets_utils.cpp sockets_unix.cpp)
list(TRANSFORM LIBCUTILS_SOCKETS_SRCS PREPEND "${LIBCUTILS}/")
aosp_library(cutils_sockets
    SRCS ${LIBCUTILS_SOCKETS_SRCS}
    FLAGS -Wno-exit-time-destructors
    INCLUDES ${SYSTEM_INCLUDES})
set(LIBCUTILS_SRCS config_utils.cpp load_file.cpp native_handle.cpp
    properties.cpp record_stream.cpp strlcpy.c canned_fs_config.cpp
    fs_config.cpp fs.cpp hashmap.cpp multiuser.cpp str_parms.cpp
    android_reboot.cpp klog.cpp partition_utils.cpp qtaguid.cpp
    trace-dev.cpp ashmem-dev.cpp)
list(TRANSFORM LIBCUTILS_SRCS PREPEND "${LIBCUTILS}/")
# -Wextra turns on the clang 22 warning about designated initializers
# again, which AOSP's clang does not give.
aosp_library(cutils
    SRCS ${LIBCUTILS_SRCS}
    FLAGS -Wno-exit-time-destructors -Werror -Wall -Wextra
        -Wno-missing-designated-field-initializers
    INCLUDES ${SYSTEM_INCLUDES})
target_link_libraries(cutils INTERFACE cutils_sockets)

aosp_library(vndksupport
    SRCS "${LIBVNDKSUPPORT}/linker.cpp"
    FLAGS -Wall -Werror
    INCLUDES "${LIBVNDKSUPPORT}/include/vndksupport"
        "${LIBVNDKSUPPORT}/include" "${LIBLOG}/include")

# libutils_defaults_nodeps with its android cflags, for libutils and
# libutils_binder.  libutils has libutils_binder in it, the android target.
set(LIBUTILS_CFLAGS -Wall -Werror -Wno-exit-time-destructors
    -DANDROID_UTILS_REF_BASE_DISABLE_IMPLICIT_CONSTRUCTION -Wthread-safety
    -fvisibility=protected)
set(LIBUTILS_BINDER_SRCS Errors.cpp RefBase.cpp SharedBuffer.cpp
    String16.cpp String8.cpp StrongPointer.cpp Unicode.cpp VectorImpl.cpp)
list(TRANSFORM LIBUTILS_BINDER_SRCS PREPEND "${LIBUTILS}/binder/")
aosp_library(utils_binder
    SRCS ${LIBUTILS_BINDER_SRCS}
    FLAGS ${LIBUTILS_CFLAGS} -Winvalid-offsetof -Wsequence-point
        -Wzero-as-null-pointer-constant
    INCLUDES ${LIBUTILS_INCLUDES} "${LIBVNDKSUPPORT}/include"
    SOONG AFDO MODULE libutils_binder)
set(LIBUTILS_SRCS FileMap.cpp JenkinsHash.cpp LightRefBase.cpp Looper.cpp
    NativeHandle.cpp Printer.cpp StopWatch.cpp SystemClock.cpp Threads.cpp
    Timers.cpp Tokenizer.cpp misc.cpp Trace.cpp)
list(TRANSFORM LIBUTILS_SRCS PREPEND "${LIBUTILS}/")
aosp_library(utils
    SRCS ${LIBUTILS_SRCS}
    FLAGS ${LIBUTILS_CFLAGS}
    INCLUDES ${LIBUTILS_INCLUDES} "${LIBVNDKSUPPORT}/include"
    SOONG AFDO MODULE libutils)
target_link_libraries(utils INTERFACE utils_binder)

# A cc_test with gtest: libc.so, libdl.so and libdl_android.so, with the
# other libraries and libc++ static.  run-gtest-suite.sh runs it in the
# jail through PT_INTERP.
#   system_test(<name> SRCS <src>... [LIBS <lib>...] [FLAGS <cflags>...]
#       [INCLUDES <dir>...] [SOONG <soong_cc options>...])
# The cflags go to C and C++.
function(system_test name)
	cmake_parse_arguments(T "" "" "SRCS;LIBS;FLAGS;INCLUDES;SOONG" ${ARGN})
	add_executable(${name} ${T_SRCS})
	soong_cc(${name} TEST GTEST ${T_SOONG})
	add_dependencies(${name} crt)
	soong_system_includes(${name} "${CXX_INCLUDE}")
	target_include_directories(${name} PRIVATE ${T_INCLUDES}
	    ${SYSTEM_INCLUDES} "${GTEST}/include")
	target_compile_options(${name} PRIVATE
	    "$<$<COMPILE_LANGUAGE:C,CXX>:${T_FLAGS}>")
	target_link_options(${name} PRIVATE "${GEN}/crtbegin_dynamic.o")
	# libc, libm and libdl are the system_shared_libs of every Android
	# program.
	target_link_libraries(${name} PRIVATE -Wl,--start-group ${T_LIBS}
	    gtest base fmtlib log ${LIBCXX_STATIC} -Wl,--end-group c_shared
	    m_shared dl_shared dl_android "${GEN}/crtend.o")
	set_target_properties(${name} PROPERTIES SKIP_BUILD_RPATH ON
	    LINK_DEPENDS "${GEN}/crtbegin_dynamic.o")
	if(BUILTINS_LIB)
		target_link_libraries(${name} PRIVATE "${BUILTINS_LIB}")
	endif()
endfunction()

set(LIBBASE_TEST_SRCS cmsg_test.cpp endian_test.cpp errors_test.cpp
    expected_test.cpp file_test.cpp function_ref_test.cpp hex_test.cpp
    logging_splitters_test.cpp logging_test.cpp macros_test.cpp
    mapped_file_test.cpp no_destructor_test.cpp parsedouble_test.cpp
    parsebool_test.cpp parseint_test.cpp parsenetaddress_test.cpp
    process_test.cpp properties_test.cpp result_test.cpp
    scopeguard_test.cpp stringify_test.cpp stringprintf_test.cpp
    strings_test.cpp test_main.cpp test_utils_test.cpp
    chrono_utils_test.cpp)
list(TRANSFORM LIBBASE_TEST_SRCS PREPEND "${LIBBASE}/")
# logging_test.cpp only gets <sys/wait.h> through googletest's Linux
# branch.  libc++ 22 marks std::get [[nodiscard]], which AOSP's libc++
# does not; expected<void>::value() calls it for its check only.
set_source_files_properties("${LIBBASE}/logging_test.cpp" PROPERTIES
    COMPILE_OPTIONS "-include;sys/wait.h")
set_source_files_properties("${LIBBASE}/result_test.cpp" PROPERTIES
    COMPILE_OPTIONS -Wno-unused-result)
system_test(libbase_test
    SRCS ${LIBBASE_TEST_SRCS}
    LIBS gmock
    FLAGS -D_FILE_OFFSET_BITS=64
    INCLUDES "${LIBBASE}" "${GMOCK}/include"
    SOONG CPP_STD gnu++23)

set(LIBLOG_TEST_SRCS libc_test.cpp liblog_default_tag.cpp
    liblog_global_state.cpp liblog_test.cpp log_id_test.cpp
    log_radio_test.cpp log_read_test.cpp log_system_test.cpp
    log_time_test.cpp log_wrap_test.cpp logd_writer_test.cpp
    logprint_test.cpp)
list(TRANSFORM LIBLOG_TEST_SRCS PREPEND "${LIBLOG}/tests/")
system_test(liblog-unit-tests
    SRCS ${LIBLOG_TEST_SRCS}
    LIBS gtest_isolated_main gtest_isolated cutils
    FLAGS -fstack-protector-all -g -Wall -Wextra -Werror -fno-builtin)

# sched_policy_test.cpp is left out until libprocessgroup is built.
set(LIBCUTILS_TEST_SRCS native_handle_test.cpp properties_test.cpp
    android_get_control_file_test.cpp android_get_control_socket_test.cpp
    fs_config_test.cpp multiuser_test.cpp str_parms_test.cpp
    trace-dev_test.cpp ashmem_base_test.cpp ashmem_test.cpp sockets_test.cpp)
list(TRANSFORM LIBCUTILS_TEST_SRCS PREPEND "${LIBCUTILS}/")
system_test(libcutils_test
    SRCS ${LIBCUTILS_TEST_SRCS}
    LIBS gtest_main cutils
    FLAGS -Wall -Wextra -Werror)

# CallStack_test.cpp is left out until libunwindstack is built.
set(LIBUTILS_TEST_SRCS BitSet_test.cpp FileMap_test.cpp LruCache_test.cpp
    Looper_test.cpp Mutex_test.cpp Singleton_test.cpp Timers_test.cpp
    SystemClock_test.cpp)
list(TRANSFORM LIBUTILS_TEST_SRCS PREPEND "${LIBUTILS}/")
system_test(libutils_test
    SRCS ${LIBUTILS_TEST_SRCS}
    LIBS gtest_main utils cutils vndksupport
    FLAGS -Wall -Wextra -Werror -Wthread-safety
    INCLUDES ${LIBUTILS_INCLUDES})

# The libraries that Singleton_test loads from the directory of the test.
function(system_test_lib name src)
	add_library(${name} SHARED "${src}")
	soong_cc(${name} TEST GTEST)
	add_dependencies(${name} crt)
	set_target_properties(${name} PROPERTIES PREFIX "" SKIP_BUILD_RPATH ON
	    LINK_DEPENDS "${GEN}/crtbegin_so.o")
	soong_system_includes(${name} "${CXX_INCLUDE}")
	target_include_directories(${name} PRIVATE ${LIBUTILS_INCLUDES})
	target_compile_options(${name} PRIVATE
	    "$<$<COMPILE_LANGUAGE:C,CXX>:-Wall;-Werror>")
	target_link_options(${name} PRIVATE "-Wl,-soname,${name}.so"
	    "${GEN}/crtbegin_so.o")
	target_link_libraries(${name} PRIVATE ${ARGN} ${LIBCXX_STATIC} c_shared
	    "${GEN}/crtend_so.o")
	if(BUILTINS_LIB)
		target_link_libraries(${name} PRIVATE "${BUILTINS_LIB}")
	endif()
endfunction()
system_test_lib(libutils_test_singleton1 "${LIBUTILS}/Singleton_test1.cpp")
system_test_lib(libutils_test_singleton2 "${LIBUTILS}/Singleton_test2.cpp"
    libutils_test_singleton1)
add_dependencies(libutils_test libutils_test_singleton1
    libutils_test_singleton2)

# libbase_test, liblog-unit-tests and libcutils_test have require_root in
# their Android.bp files, so they run as root in the jail (-r).  Only
# liblog-unit-tests is an isolated test; Android runs the other suites in
# one process, so their tests run one at a time (-s).  The singleton
# libraries go to the jail with libutils_test (-d), as data_libs.
foreach(suite libbase_test liblog-unit-tests libcutils_test libutils_test)
	string(REPLACE "-" "_" t ${suite})
	set(as_root -r)
	set(serial -s)
	set(data)
	if(suite STREQUAL "libutils_test")
		set(as_root)
		set(data -d "$<TARGET_FILE:libutils_test_singleton1>"
		    -d "$<TARGET_FILE:libutils_test_singleton2>")
	elseif(suite STREQUAL "liblog-unit-tests")
		set(serial)
	endif()
	add_test(NAME ${t} COMMAND ${RUN_SUITE}
	    -j "${GEN}/bionic-tests-jail.conf" ${data} ${as_root} ${serial}
	    "${CMAKE_CURRENT_SOURCE_DIR}/${suite}.excluded"
	    "$<TARGET_FILE:linker64>" "$<TARGET_FILE:${suite}>")
	set_tests_properties(${t} PROPERTIES
	    ENVIRONMENT "LD_LIBRARY_PATH=${GEN};${RUN_SUITE_PATH}")
endforeach()

# libutils_freebsd_test: androidSetThreadName() on bionic-freebsd.
system_test(libutils_freebsd_test
    SRCS "${CMAKE_CURRENT_SOURCE_DIR}/libutils_freebsd_test.cpp"
    LIBS gtest_main utils cutils vndksupport
    INCLUDES ${LIBUTILS_INCLUDES})
add_test(NAME libutils_freebsd_test COMMAND ${RUN_SUITE}
    -j "${GEN}/bionic-tests-jail.conf"
    "${CMAKE_CURRENT_SOURCE_DIR}/libutils_freebsd_test.excluded"
    "$<TARGET_FILE:linker64>" "$<TARGET_FILE:libutils_freebsd_test>")
set_tests_properties(libutils_freebsd_test PROPERTIES
    ENVIRONMENT "LD_LIBRARY_PATH=${GEN};${RUN_SUITE_PATH}")

# zlib_tests: the cc_test of external/zlib, with libz.so and the static
# zlib_google_compression_utils_portable of libz_defaults.  Its files
# include "gtest.h", so googletest's include/gtest is on the include path,
# as in the Android.bp.  Android runs it in one process and not as root,
# so its tests run one at a time (-s) as the calling user.
aosp_library(zlib_google_compression_utils_portable
    SRCS "${ZLIB}/google/compression_utils_portable.cc"
    FLAGS ${ZLIB_FLAGS}
    INCLUDES "${ZLIB}" "${ZLIB}/google"
    SOONG EXTERNAL)
system_test(zlib_tests
    SRCS "${ZLIB}/contrib/tests/infcover.cc"
        "${ZLIB}/contrib/tests/utils_unittest.cc"
    LIBS gtest_main zlib_google_compression_utils_portable z_shared
    FLAGS -DCMAKE_STANDALONE_UNITTESTS -Wno-unused-parameter
    INCLUDES "${ZLIB}" "${ZLIB}/google" "${GTEST}/include/gtest"
    SOONG EXTERNAL)
add_test(NAME zlib_tests COMMAND ${RUN_SUITE}
    -j "${GEN}/bionic-tests-jail.conf" -s
    "${CMAKE_CURRENT_SOURCE_DIR}/zlib_tests.excluded"
    "$<TARGET_FILE:linker64>" "$<TARGET_FILE:zlib_tests>")
set_tests_properties(zlib_tests PROPERTIES
    ENVIRONMENT "LD_LIBRARY_PATH=${GEN};${RUN_SUITE_PATH}")
