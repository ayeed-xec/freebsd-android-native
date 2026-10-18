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
# bionic-unit-tests-static and bionic-unit-tests with the elftls, fdsan,
# malloc, pthread, semaphore, setjmp, signal, stdio, string,
# stack_protector, sys_mman, system_properties, time and unistd tests.  Flags follow
# bionic_tests_defaults in bionic's tests/Android.bp.  The dynamic suite
# links against libc.so and starts through PT_INTERP /system/bin/linker64.
# It also has the dlext, dlfcn, elftls_dl and link tests, and the libraries
# and helper programs of tests/libs that they use.  Both suites run in a
# jail on the Android root, as on a device, because the helper programs
# start through linker64 and the property tests need the property service
# of the jail.  Run them in the dev VM with
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
    buffer_tests.cpp stack_protector_test_helper.cpp elftls_test.cpp
    fdsan_test.cpp malloc_test.cpp pthread_test.cpp semaphore_test.cpp
    setjmp_test.cpp signal_test.cpp stdio_test.cpp string_test.cpp
    stack_protector_test.cpp sys_epoll_test.cpp sys_mman_test.cpp
    sys_select_test.cpp sys_xattr_test.cpp
    system_properties_test.cpp eventfd_test.cpp
    sys_socket_cred_test.cpp
    system_properties_test2.cpp time_test.cpp unistd_test.cpp)
list(TRANSFORM BIONIC_TEST_SRCS PREPEND "${BIONIC_TESTS}/")
# The part of libBionicLoaderTests that the dynamic suite builds, and
# libBionicElfTlsLoaderTests.
set(BIONIC_LOADER_TEST_SRCS dlext_test.cpp dlfcn_symlink_support.cpp
    dlfcn_test.cpp elftls_dl_test.cpp link_test.cpp)
list(TRANSFORM BIONIC_LOADER_TEST_SRCS PREPEND "${BIONIC_TESTS}/")

# The exec tests run echo, printenv and sh from BIN_DIR, and look for echo
# and printenv in PATH; the popen tests run cat.  On Android these are
# toybox and mksh in /system/bin.  There is no toybox yet, so copies of the
# FreeBSD programs stand in for it.  They are copies, not links: in the jail
# /bin is /system/bin.
set(TEST_BIN "${CMAKE_CURRENT_BINARY_DIR}/test-bin")
file(MAKE_DIRECTORY "${TEST_BIN}")
foreach(prog /bin/cat /bin/echo /bin/sh /usr/bin/printenv)
	get_filename_component(name "${prog}" NAME)
	# An older tree has a link here, and a copy would go to its target.
	file(REMOVE "${TEST_BIN}/${name}")
	file(COPY "${prog}" DESTINATION "${TEST_BIN}")
endforeach()

# Both suites link the same objects.  The loader tests are in the dynamic
# suite only.
add_library(bionic_test_objs OBJECT ${BIONIC_TEST_SRCS})
add_library(bionic_loader_test_objs OBJECT ${BIONIC_LOADER_TEST_SRCS})
target_include_directories(bionic_loader_test_objs PRIVATE
    "${BIONIC_TESTS}/libs" "${ZIPARCHIVE}/include"
    "${AOSP_SYSTEM}/libprocinfo/include")
# dlfcn_test and link_test test "#if __arm__".
target_compile_options(bionic_loader_test_objs PRIVATE -Wno-undef)
foreach(objs bionic_test_objs bionic_loader_test_objs)
	target_include_directories(${objs} SYSTEM BEFORE PRIVATE
	    "${CXX_INCLUDE}")
	target_include_directories(${objs} PRIVATE "${LIBC}"
	    "${LIBC}/platform" "${LIBC}/system_properties/include"
	    "${PROPINFO}/include" "${BIONIC_TESTS}" "${GTEST}/include"
	    "${GTEST_ISOLATED}/include" "${LIBBASE}/include"
	    "${LIBLOG}/include" "${AOSP_SYSTEM}/core/libcutils/include"
	    "${TINYXML2}")
	target_compile_definitions(${objs} PRIVATE
	    "BIN_DIR=\"${TEST_BIN}/\"")
	# -Wextra goes first so AOSP's -Wno-* flags still win.  clang 22
	# warns about function type casts where AOSP's clang does not.
	# mode_t is 16 bits on FreeBSD, so st_mode & 0777 promotes to int
	# and trips -Wsign-compare against the tests' unsigned constants.
	target_compile_options(${objs} PRIVATE -std=gnu++20
	    -Wextra ${AOSP_CXX_FLAGS} -fstack-protector-all -Wunused
	    -fno-builtin -Wno-deprecated-declarations -Wno-invalid-offsetof
	    -Wno-reorder-init-list -Wno-cast-function-type-mismatch
	    -Wno-sign-compare -fsanitize=shadow-call-stack)
endforeach()
set(LIBCXX_STATIC "${BIONIC_SYSROOT}/usr/lib/libc++.a"
    "${BIONIC_SYSROOT}/usr/lib/libc++abi.a")
set(BIONIC_TEST_LIBS -Wl,--start-group gtest_isolated gtest tinyxml2 base log
    m_static ${LIBCXX_STATIC} -Wl,--end-group)

# The libraries of tests/libs that the loader tests load, as in
# bionic_testlib_defaults: libc.so, static libc++, -Wl,--no-undefined and
# DT_RUNPATH $ORIGIN.  They go in bionic-loader-test-libs next to the test
# binary.  GetTestLibRoot() finds that directory from AT_EXECPATH, which
# names linker64 when the suite runs as "linker64 bionic-unit-tests";
# linker64 is in the same directory.
set(TESTLIB_SRC "${BIONIC_TESTS}/libs")
set(TESTLIB_DIR "${CMAKE_CURRENT_BINARY_DIR}/bionic-loader-test-libs")
function(bionic_test_lib name)
	cmake_parse_arguments(L "UNDEFINED" "DIR;SONAME;MAP"
	    "SRCS;LIBS;FLAGS;LDFLAGS" ${ARGN})
	list(TRANSFORM L_SRCS PREPEND "${TESTLIB_SRC}/")
	if(NOT L_SONAME)
		set(L_SONAME ${name}.so)
	endif()
	add_library(${name} SHARED ${L_SRCS})
	add_dependencies(${name} crt)
	set_target_properties(${name} PROPERTIES PREFIX "" NO_SONAME ON
	    SKIP_BUILD_RPATH ON LIBRARY_OUTPUT_DIRECTORY "${TESTLIB_DIR}/${L_DIR}"
	    LINK_DEPENDS "${GEN}/crtbegin_so.o")
	target_include_directories(${name} SYSTEM BEFORE PRIVATE
	    "${CXX_INCLUDE}")
	target_compile_options(${name} PRIVATE -std=gnu++20 -Wall -Werror
	    ${AOSP_CXX_FLAGS} ${L_FLAGS})
	if(NOT L_UNDEFINED)
		target_link_options(${name} PRIVATE -Wl,--no-undefined)
	endif()
	if(L_MAP)
		target_link_options(${name} PRIVATE
		    "-Wl,--version-script=${TESTLIB_SRC}/${L_MAP}")
	endif()
	# arm64 Android ELFs have 16 KiB alignment; the lld default is 64 KiB.
	# The dlext tests load three of these libraries into one 1 MiB
	# reservation.
	target_link_options(${name} PRIVATE -nostdlib -fuse-ld=lld
	    "-Wl,-soname,${L_SONAME}" "-Wl,-rpath,\$ORIGIN"
	    -Wl,--enable-new-dtags -Wl,-z,max-page-size=16384 ${L_LDFLAGS}
	    "${GEN}/crtbegin_so.o")
	target_link_libraries(${name} PRIVATE ${L_LIBS} ${LIBCXX_STATIC}
	    c_shared dl_shared "${GEN}/crtend_so.o")
	if(BUILTINS_LIB)
		target_link_libraries(${name} PRIVATE "${BUILTINS_LIB}")
	endif()
endfunction()

bionic_test_lib(libatest_simple_zip DIR libatest_simple_zip SRCS
    dlopen_testlib_simple.cpp)
bionic_test_lib(libdl_test_df_1_global SRCS dl_df_1_global.cpp LDFLAGS
    -Wl,-z,global)
bionic_test_lib(libdlext_test SRCS dlext_test_library.cpp LIBS libtest_simple
    LDFLAGS -Wl,-z,relro)
bionic_test_lib(libdlext_test_different_soname SONAME libdlext_test_soname.so
    SRCS dlext_test_library.cpp)
bionic_test_lib(libdlext_test_fd DIR libdlext_test_fd SRCS
    dlext_test_library.cpp LIBS libtest_simple LDFLAGS
    "-Wl,-rpath,\$ORIGIN/..")
bionic_test_lib(libdlext_test_norelro SRCS dlext_test_library.cpp LIBS
    libtest_simple LDFLAGS -Wl,-z,norelro)
bionic_test_lib(libdlext_test_recursive SRCS dlext_test_recursive_library.cpp
    LIBS libdlext_test LDFLAGS -Wl,-z,relro)
bionic_test_lib(libdlext_test_zip DIR libdlext_test_zip SRCS
    dlext_test_library.cpp LIBS libatest_simple_zip)
bionic_test_lib(libgnu-hash-table-library SRCS dlext_test_library.cpp LDFLAGS
    -Wl,--hash-style=gnu)
bionic_test_lib(libns_hidden_child_app DIR ns_hidden_child_app SRCS
    ns_hidden_child_app.cpp LIBS libns_hidden_child_public)
bionic_test_lib(libns_hidden_child_global SRCS ns_hidden_child_global.cpp
    LIBS libns_hidden_child_internal LDFLAGS -Wl,-z,global)
bionic_test_lib(libns_hidden_child_internal SRCS ns_hidden_child_internal.cpp)
bionic_test_lib(libns_hidden_child_public SRCS ns_hidden_child_public.cpp
    LIBS libns_hidden_child_internal)
bionic_test_lib(libnstest_dlopened DIR private_namespace_libs SRCS
    namespaces_dlopened.cpp)
bionic_test_lib(libnstest_ns_a_public1 DIR ns_a SRCS libnstest_ns_a_public1.cpp
    LIBS libnstest_ns_a_public1_internal libnstest_ns_b_public3)
bionic_test_lib(libnstest_ns_a_public1_internal DIR ns_a SRCS
    libnstest_ns_a_public1_internal.cpp)
bionic_test_lib(libnstest_ns_b_public2 DIR ns_b SRCS libnstest_ns_b_public2.cpp
    LIBS libnstest_ns_a_public1)
bionic_test_lib(libnstest_ns_b_public3 DIR ns_b SRCS
    libnstest_ns_b_public3.cpp)
bionic_test_lib(libnstest_private DIR private_namespace_libs SRCS
    namespaces_private.cpp)
bionic_test_lib(libnstest_private_external DIR private_namespace_libs_external
    SRCS namespaces_private.cpp)
bionic_test_lib(libnstest_public DIR public_namespace_libs SRCS
    namespaces_public.cpp LIBS libnstest_public_internal)
bionic_test_lib(libnstest_public_internal DIR public_namespace_libs SRCS
    namespaces_public_internal.cpp)
bionic_test_lib(libnstest_root DIR private_namespace_libs SRCS
    namespaces_root.cpp LIBS libnstest_public libnstest_private)
bionic_test_lib(libnstest_root_not_isolated DIR private_namespace_libs SRCS
    namespaces_root.cpp LIBS libnstest_public libnstest_private_external
    LDFLAGS "-Wl,-rpath,\$ORIGIN/../private_namespace_libs_external")
bionic_test_lib(libsegment_gap_inner SRCS segment_gap_inner.cpp)
bionic_test_lib(libsegment_gap_outer SRCS segment_gap_outer.cpp LDFLAGS
    "-Wl,-T,${TESTLIB_SRC}/segment_gap_outer.lds")
bionic_test_lib(libsysv-hash-table-library SRCS dlext_test_library.cpp LDFLAGS
    -Wl,--hash-style=sysv)
bionic_test_lib(libtest_check_order_dlsym SRCS empty.cpp LIBS
    libtest_check_order_dlsym_1_left libtest_check_order_dlsym_2_right
    libtest_check_order_dlsym_3_c)
bionic_test_lib(libtest_check_order_dlsym_1_left SRCS empty.cpp LIBS
    libtest_check_order_dlsym_a libtest_check_order_dlsym_b)
bionic_test_lib(libtest_check_order_dlsym_2_right SRCS
    dlopen_check_order_dlsym_answer.cpp FLAGS -D__ANSWER=42)
bionic_test_lib(libtest_check_order_dlsym_3_c SRCS
    dlopen_check_order_dlsym_answer.cpp FLAGS -D__ANSWER=3)
bionic_test_lib(libtest_check_order_dlsym_a SRCS
    dlopen_check_order_dlsym_answer.cpp FLAGS -D__ANSWER=1)
bionic_test_lib(libtest_check_order_dlsym_b SRCS
    dlopen_check_order_dlsym_answer.cpp FLAGS -D__ANSWER=2 -D__ANSWER2=43)
bionic_test_lib(libtest_check_order_reloc_root SRCS
    dlopen_check_order_reloc_root_answer.cpp LIBS
    libtest_check_order_reloc_root_1 libtest_check_order_reloc_root_2)
bionic_test_lib(libtest_check_order_reloc_root_1 SRCS empty.cpp)
bionic_test_lib(libtest_check_order_reloc_root_2 SRCS
    dlopen_check_order_reloc_root_answer_impl.cpp FLAGS -D__ANSWER=2)
bionic_test_lib(libtest_check_order_reloc_siblings SRCS empty.cpp LIBS
    libtest_check_order_reloc_siblings_1 libtest_check_order_reloc_siblings_2
    libtest_check_order_reloc_siblings_3)
bionic_test_lib(libtest_check_order_reloc_siblings_1 SRCS empty.cpp LIBS
    libtest_check_order_reloc_siblings_a libtest_check_order_reloc_siblings_b)
bionic_test_lib(libtest_check_order_reloc_siblings_2 UNDEFINED SRCS
    dlopen_check_order_reloc_grandchild_answer.cpp LIBS
    libtest_check_order_reloc_siblings_c libtest_check_order_reloc_siblings_d)
bionic_test_lib(libtest_check_order_reloc_siblings_3 SRCS
    dlopen_check_order_reloc_nephew_answer.cpp LIBS
    libtest_check_order_reloc_siblings_e libtest_check_order_reloc_siblings_f)
bionic_test_lib(libtest_check_order_reloc_siblings_a SRCS
    dlopen_check_order_reloc_answer_impl.cpp FLAGS -D__ANSWER=42)
bionic_test_lib(libtest_check_order_reloc_siblings_b SRCS
    dlopen_check_order_reloc_answer_impl.cpp FLAGS -D__ANSWER=1)
bionic_test_lib(libtest_check_order_reloc_siblings_c SRCS
    dlopen_check_order_reloc_answer_impl.cpp LIBS
    libtest_check_order_reloc_siblings_c_1
    libtest_check_order_reloc_siblings_c_2 FLAGS -D__ANSWER=2)
bionic_test_lib(libtest_check_order_reloc_siblings_c_1 SRCS
    dlopen_check_order_reloc_grandchild_answer_impl.cpp FLAGS -D__ANSWER=42)
bionic_test_lib(libtest_check_order_reloc_siblings_c_2 SRCS
    dlopen_check_order_reloc_grandchild_answer_impl.cpp FLAGS -D__ANSWER=0)
bionic_test_lib(libtest_check_order_reloc_siblings_d SRCS
    dlopen_check_order_reloc_answer_impl.cpp FLAGS -D__ANSWER=3)
bionic_test_lib(libtest_check_order_reloc_siblings_e SRCS
    dlopen_check_order_reloc_answer_impl.cpp FLAGS -D__ANSWER=4)
bionic_test_lib(libtest_check_order_reloc_siblings_f SRCS
    dlopen_check_order_reloc_answer.cpp)
bionic_test_lib(libtest_check_rtld_next_from_library SRCS
    check_rtld_next_from_library.cpp)
bionic_test_lib(libtest_dlopen_df_1_global SRCS dl_df_1_global_dummy.cpp
    LDFLAGS -Wl,-z,global)
bionic_test_lib(libtest_dlopen_from_ctor SRCS
    dlopen_testlib_dlopen_from_ctor.cpp)
bionic_test_lib(libtest_dlopen_from_ctor_main SRCS empty.cpp LIBS
    libtest_dlopen_from_ctor)
bionic_test_lib(libtest_dlopen_weak_undefined_func SRCS
    dlopen_weak_undefined.cpp)
bionic_test_lib(libtest_dlsym_df_1_global SRCS dl_df_1_use_global.cpp)
bionic_test_lib(libtest_dlsym_from_this SRCS dlsym_from_this_symbol.cpp LIBS
    libtest_dlsym_from_this_child)
bionic_test_lib(libtest_dlsym_from_this_child SRCS
    dlsym_from_this_functions.cpp LIBS libtest_dlsym_from_this_grandchild)
bionic_test_lib(libtest_dlsym_from_this_grandchild SRCS
    dlsym_from_this_symbol2.cpp)
bionic_test_lib(libtest_dlsym_weak_func SRCS dlsym_weak_function.cpp)
bionic_test_lib(libtest_dt_runpath_a DIR dt_runpath_a SRCS empty.cpp)
bionic_test_lib(libtest_dt_runpath_b DIR dt_runpath_b_c_x SRCS empty.cpp LIBS
    libtest_dt_runpath_a LDFLAGS "-Wl,-rpath,\$ORIGIN/../dt_runpath_a")
bionic_test_lib(libtest_dt_runpath_c DIR dt_runpath_b_c_x SRCS empty.cpp LIBS
    libtest_dt_runpath_a LDFLAGS "-Wl,-rpath,\$ORIGIN/invalid_dt_runpath")
bionic_test_lib(libtest_dt_runpath_d SRCS dlopen_b.cpp LIBS
    libtest_dt_runpath_b libtest_dt_runpath_c libtest_dt_runpath_y LDFLAGS
    "-Wl,-rpath,\$ORIGIN/dt_runpath_b_c_x"
    "-Wl,-rpath,\$ORIGIN/dt_runpath_y/\$LIB")
# Only the runpath zip has this one.
bionic_test_lib(libtest_dt_runpath_d_zip DIR libtest_dt_runpath_d_zip SRCS
    dlopen_b.cpp LIBS libtest_dt_runpath_b libtest_dt_runpath_c
    libtest_dt_runpath_y LDFLAGS "-Wl,-rpath,\$ORIGIN/dt_runpath_b_c_x"
    "-Wl,-rpath,\$ORIGIN/dt_runpath_y/\$LIB")
bionic_test_lib(libtest_dt_runpath_x DIR dt_runpath_b_c_x SRCS empty.cpp)
bionic_test_lib(libtest_dt_runpath_y DIR dt_runpath_y/lib64 SRCS empty.cpp)
bionic_test_lib(libtest_elftls_dynamic SRCS elftls_dynamic.cpp LIBS
    libtest_elftls_shared_var)
foreach(n 1 2 3 4 5)
	bionic_test_lib(libtest_elftls_dynamic_filler_${n} SRCS
	    elftls_dynamic_filler.cpp FLAGS -DTLS_FILLER=${n}00)
endforeach()
bionic_test_lib(libtest_elftls_shared_var SRCS elftls_shared_var.cpp)
bionic_test_lib(libtest_elftls_shared_var_ie SRCS elftls_shared_var_ie.cpp
    LIBS libtest_elftls_shared_var)
bionic_test_lib(libtest_elftls_tprel SRCS elftls_tprel.cpp)
# The static suite links the static variants of the two libraries that
# elftls_test uses, as Android does.
foreach(name elftls_shared_var elftls_tprel)
	add_library(libtest_${name}_static STATIC "${TESTLIB_SRC}/${name}.cpp")
	target_include_directories(libtest_${name}_static SYSTEM BEFORE
	    PRIVATE "${CXX_INCLUDE}")
	target_compile_options(libtest_${name}_static PRIVATE -std=gnu++20
	    -Wall -Werror ${AOSP_CXX_FLAGS})
endforeach()
# Android links device code with -z now, so libtest_empty.so has DT_FLAGS.
# gen_invalid_elf makes the textrels files from that entry.
bionic_test_lib(libtest_empty SRCS empty.cpp LDFLAGS -Wl,-z,now)
bionic_test_lib(libtest_ifunc SRCS dlopen_testlib_ifunc.cpp)
bionic_test_lib(libtest_ifunc_variable SRCS dlopen_testlib_ifunc_variable.cpp
    LIBS libtest_ifunc_variable_impl)
bionic_test_lib(libtest_ifunc_variable_impl SRCS
    dlopen_testlib_ifunc_variable_impl.cpp)
bionic_test_lib(libtest_indirect_thread_local_dtor SRCS empty.cpp LIBS
    libtest_thread_local_dtor libtest_thread_local_dtor2)
bionic_test_lib(libtest_init_fini_order_child SRCS
    dlopen_check_init_fini_child.cpp LIBS libtest_init_fini_order_grand_child)
bionic_test_lib(libtest_init_fini_order_grand_child SRCS
    dlopen_check_init_fini_grand_child.cpp)
bionic_test_lib(libtest_init_fini_order_root SRCS
    dlopen_check_init_fini_root.cpp LIBS libtest_init_fini_order_child
    libtest_init_fini_order_grand_child)
bionic_test_lib(libtest_init_fini_order_root2 SRCS
    dlopen_check_init_fini_root.cpp LIBS libtest_init_fini_order_grand_child
    libtest_init_fini_order_child)
bionic_test_lib(libtest_missing_symbol DIR public_namespace_libs UNDEFINED
    SRCS dlopen_testlib_missing_symbol.cpp)
bionic_test_lib(libtest_missing_symbol_child_private DIR
    private_namespace_libs SRCS empty.cpp LIBS libnstest_public)
bionic_test_lib(libtest_missing_symbol_child_public DIR public_namespace_libs
    SRCS empty.cpp LIBS libnstest_public)
bionic_test_lib(libtest_missing_symbol_root DIR private_namespace_libs
    UNDEFINED SRCS dlopen_testlib_missing_symbol.cpp LIBS libnstest_public
    libtest_missing_symbol_child_public libtest_missing_symbol_child_private)
bionic_test_lib(libtest_nodelete_1 SRCS dlopen_nodelete_1.cpp)
bionic_test_lib(libtest_nodelete_2 SRCS dlopen_nodelete_2.cpp)
bionic_test_lib(libtest_nodelete_dt_flags_1 SRCS
    dlopen_nodelete_dt_flags_1.cpp LDFLAGS -Wl,-z,nodelete)
bionic_test_lib(libtest_relo_check_dt_needed_order SRCS
    dlopen_testlib_relo_check_dt_needed_order.cpp LIBS
    libtest_relo_check_dt_needed_order_1 libtest_relo_check_dt_needed_order_2)
bionic_test_lib(libtest_relo_check_dt_needed_order_1 SRCS
    dlopen_testlib_relo_check_dt_needed_order_1.cpp)
bionic_test_lib(libtest_relo_check_dt_needed_order_2 SRCS
    dlopen_testlib_relo_check_dt_needed_order_2.cpp)
bionic_test_lib(libtest_simple SRCS dlopen_testlib_simple.cpp)
bionic_test_lib(libtest_thread_local_dtor SRCS thread_local_dtor.cpp)
bionic_test_lib(libtest_thread_local_dtor2 SRCS thread_local_dtor2.cpp)
bionic_test_lib(libtest_two_parents_child SRCS
    dlopen_2_parents_reloc_answer.cpp)
bionic_test_lib(libtest_two_parents_parent1 SRCS
    dlopen_check_order_reloc_answer_impl.cpp LIBS libtest_two_parents_child
    FLAGS -D__ANSWER=42)
bionic_test_lib(libtest_two_parents_parent2 SRCS
    dlopen_check_order_reloc_answer_impl.cpp LIBS libtest_two_parents_child
    FLAGS -D__ANSWER=1)
bionic_test_lib(libtest_versioned_lib MAP versioned_lib_v3.map SRCS
    versioned_lib_v3.cpp)
bionic_test_lib(libtest_versioned_libv1 SONAME libtest_versioned_lib.so MAP
    versioned_lib_v1.map SRCS versioned_lib_v1.cpp)
bionic_test_lib(libtest_versioned_libv2 SONAME libtest_versioned_lib.so MAP
    versioned_lib_v2.map SRCS versioned_lib_v2.cpp)
bionic_test_lib(libtest_versioned_otherlib MAP versioned_lib_other.map SRCS
    versioned_lib_other.cpp)
bionic_test_lib(libtest_versioned_otherlib_empty SONAME
    libtest_versioned_otherlib.so SRCS empty.cpp)
bionic_test_lib(libtest_versioned_uselibv1 SRCS versioned_uselib.cpp LIBS
    libtest_versioned_libv1)
bionic_test_lib(libtest_versioned_uselibv2 MAP versioned_uselib.map SRCS
    versioned_uselib.cpp LIBS libtest_versioned_libv2)
bionic_test_lib(libtest_versioned_uselibv2_other SRCS versioned_uselib.cpp
    LIBS libtest_versioned_otherlib_empty libtest_versioned_libv2)
bionic_test_lib(libtest_versioned_uselibv3_other SRCS versioned_uselib.cpp
    LIBS libtest_versioned_otherlib_empty libtest_versioned_lib)
bionic_test_lib(libtest_with_dependency SRCS dlopen_testlib_simple.cpp LIBS
    libdlext_test)
bionic_test_lib(libtest_with_dependency_loop SRCS
    dlopen_testlib_loopy_root.cpp LIBS libtest_with_dependency_loop_a)
bionic_test_lib(libtest_with_dependency_loop_a SRCS dlopen_testlib_loopy_a.cpp
    LIBS libtest_with_dependency_loop_b_tmp)
bionic_test_lib(libtest_with_dependency_loop_b SRCS dlopen_testlib_loopy_b.cpp
    LIBS libtest_with_dependency_loop_c)
bionic_test_lib(libtest_with_dependency_loop_b_tmp SONAME
    libtest_with_dependency_loop_b.so SRCS dlopen_testlib_loopy_invalid.cpp)
bionic_test_lib(libtest_with_dependency_loop_c SRCS dlopen_testlib_loopy_c.cpp
    LIBS libtest_with_dependency_loop_a)
bionic_test_lib(libtestshared DIR inaccessible_libs SRCS empty.cpp)

# The zips that the dlext tests open libraries from.  Android stores the
# files with soong_zip -L 0, and bionic_tests_zipalign then puts the data
# of each entry at a 16 KiB boundary, so that linker64 can map it.  Here
# bsdtar(1) stores the files, and the zipalign tool is a static bionic
# program.
aosp_library(ziparchive_writer
    SRCS "${ZIPARCHIVE}/zip_writer.cc"
    FLAGS -std=gnu++20 -DZLIB_CONST -Wno-missing-field-initializers
    INCLUDES "${ZIPARCHIVE}/include" "${LIBBASE}/include" "${LIBLOG}/include"
        "${ZLIB_SRC}" "${GTEST}/include")
add_executable(bionic_tests_zipalign "${TESTLIB_SRC}/bionic_tests_zipalign.cpp")
add_dependencies(bionic_tests_zipalign crt)
target_include_directories(bionic_tests_zipalign SYSTEM BEFORE PRIVATE
    "${CXX_INCLUDE}")
target_include_directories(bionic_tests_zipalign PRIVATE
    "${ZIPARCHIVE}/include" "${LIBBASE}/include" "${GTEST}/include")
target_compile_options(bionic_tests_zipalign PRIVATE -std=gnu++20 -Wall
    -Werror ${AOSP_CXX_FLAGS} -DZIPARCHIVE_DISABLE_CALLBACK_API=0)
target_link_options(bionic_tests_zipalign PRIVATE -static -nostdlib
    -fuse-ld=lld -Wl,--gc-sections "${GEN}/crtbegin_static.o")
target_link_libraries(bionic_tests_zipalign PRIVATE -Wl,--start-group
    ziparchive_writer ziparchive z base log ${LIBCXX_STATIC} -Wl,--end-group
    c_static "${GEN}/crtend.o")
set_target_properties(bionic_tests_zipalign PROPERTIES
    LINK_DEPENDS "${GEN}/crtbegin_static.o")
if(BUILTINS_LIB)
	target_link_libraries(bionic_tests_zipalign PRIVATE "${BUILTINS_LIB}")
endif()

# bionic_test_zip(<name> <target>:<directory> ...) writes
# <name>/<name>_zipaligned.zip with each library in its directory.
function(bionic_test_zip name)
	set(tmp "${CMAKE_CURRENT_BINARY_DIR}/${name}")
	set(out "${TESTLIB_DIR}/${name}/${name}_zipaligned.zip")
	set(copies)
	set(libs)
	foreach(entry ${ARGN})
		string(REPLACE ":" ";" entry "${entry}")
		list(GET entry 0 lib)
		list(GET entry 1 dir)
		list(APPEND copies COMMAND "${CMAKE_COMMAND}" -E make_directory
		    "${tmp}/${dir}" COMMAND "${CMAKE_COMMAND}" -E copy
		    "$<TARGET_FILE:${lib}>" "${tmp}/${dir}")
		list(APPEND libs ${lib})
	endforeach()
	add_custom_command(OUTPUT "${out}"
	    COMMAND "${CMAKE_COMMAND}" -E rm -rf "${tmp}"
	    ${copies}
	    COMMAND "${CMAKE_COMMAND}" -E touch "${tmp}/empty_file.txt"
	    COMMAND tar -c -f "${tmp}.unaligned" --format zip
	        --options zip:compression=store -C "${tmp}" libdir
	        empty_file.txt
	    COMMAND "${CMAKE_COMMAND}" -E make_directory "${TESTLIB_DIR}/${name}"
	    COMMAND bionic_tests_zipalign 16384 "${tmp}.unaligned" "${out}"
	    DEPENDS ${libs} bionic_tests_zipalign VERBATIM)
	add_custom_target(${name}_zipaligned ALL DEPENDS "${out}")
endfunction()
bionic_test_zip(libdlext_test_zip libdlext_test_zip:libdir
    libatest_simple_zip:libdir)
bionic_test_zip(libdlext_test_runpath_zip libtest_dt_runpath_d_zip:libdir
    libtest_dt_runpath_a:libdir/dt_runpath_a
    libtest_dt_runpath_b:libdir/dt_runpath_b_c_x
    libtest_dt_runpath_c:libdir/dt_runpath_b_c_x
    libtest_dt_runpath_x:libdir/dt_runpath_b_c_x
    libtest_dt_runpath_y:libdir/dt_runpath_y/lib64)
file(COPY "${BIONIC_TESTS}/prebuilt-elf-files/arm64/libtest_invalid-local-tls.so"
    DESTINATION "${TESTLIB_DIR}/prebuilt-elf-files")

# The invalid ELF files of the dlfcn tests.  Android makes them from
# libtest_empty.so with gen_invalid_elf from system/memory/libmeminfo.  As
# with bionic_tests_zipalign, the tool is a static bionic program; it uses
# only the headers of libbase.
set(LIBELFUTILS "${AOSP_SYSTEM}/memory/libmeminfo/libelfutils")
if(NOT EXISTS "${LIBELFUTILS}/tools/gen_invalid_elf.cpp")
	message(FATAL_ERROR "${LIBELFUTILS} is missing; run aosp/fetch.sh "
	    "--project platform/system/memory/libmeminfo:libelfutils")
endif()
add_executable(gen_invalid_elf "${LIBELFUTILS}/tools/gen_invalid_elf.cpp"
    "${LIBELFUTILS}/elf-file.cpp")
add_dependencies(gen_invalid_elf crt)
target_include_directories(gen_invalid_elf SYSTEM BEFORE PRIVATE
    "${CXX_INCLUDE}")
target_include_directories(gen_invalid_elf PRIVATE "${LIBELFUTILS}/include"
    "${LIBBASE}/include")
target_compile_options(gen_invalid_elf PRIVATE -std=gnu++20 -Wall -Werror
    ${AOSP_CXX_FLAGS})
target_link_options(gen_invalid_elf PRIVATE -static -nostdlib -fuse-ld=lld
    -Wl,--gc-sections "${GEN}/crtbegin_static.o")
target_link_libraries(gen_invalid_elf PRIVATE ${LIBCXX_STATIC} c_static
    "${GEN}/crtend.o")
set_target_properties(gen_invalid_elf PROPERTIES
    LINK_DEPENDS "${GEN}/crtbegin_static.o")
if(BUILTINS_LIB)
	target_link_libraries(gen_invalid_elf PRIVATE "${BUILTINS_LIB}")
endif()

# <type>[:<name>]: the --invalid-type and the name of the
# cc_prebuilt_library_shared module in tests/Android.bp.
set(invalid_elfs)
foreach(entry rwx_load_segment:rw_load_segment unaligned_shdr_offset
    zero_shentsize zero_shstrndx empty_shdr_table zero_shdr_table_offset
    zero_shdr_table_content textrels textrels2)
	string(REPLACE ":" ";" entry "${entry}")
	list(GET entry 0 type)
	list(GET entry -1 name)
	set(out "${TESTLIB_DIR}/prebuilt-elf-files/libtest_invalid-${name}.so")
	add_custom_command(OUTPUT "${out}"
	    COMMAND gen_invalid_elf "--ref-elf=$<TARGET_FILE:libtest_empty>"
	        "--output=${out}" "--invalid-type=${type}"
	    DEPENDS gen_invalid_elf libtest_empty VERBATIM)
	list(APPEND invalid_elfs "${out}")
endforeach()
add_custom_target(bionic_invalid_elfs ALL DEPENDS ${invalid_elfs})

# The helper programs that the dlext, elftls and elftls_dl tests run with
# execve, cc_test modules with bionic_testlib_defaults.  Their PT_INTERP is
# /system/bin/linker64, so they only start in the jail.
function(bionic_test_helper name)
	cmake_parse_arguments(H "" "" "INCLUDES;LIBS;LDFLAGS" ${ARGN})
	add_executable(${name} "${TESTLIB_SRC}/${name}.cpp")
	add_dependencies(${name} crt)
	set_target_properties(${name} PROPERTIES SKIP_BUILD_RPATH ON
	    RUNTIME_OUTPUT_DIRECTORY "${TESTLIB_DIR}"
	    LINK_DEPENDS "${GEN}/crtbegin_dynamic.o")
	target_include_directories(${name} SYSTEM BEFORE PRIVATE
	    "${CXX_INCLUDE}")
	target_include_directories(${name} PRIVATE ${H_INCLUDES})
	target_compile_options(${name} PRIVATE -std=gnu++20 -Wall -Werror
	    ${AOSP_CXX_FLAGS})
	target_link_options(${name} PRIVATE -nostdlib -fuse-ld=lld -pie
	    -Wl,--dynamic-linker=/system/bin/linker64 "-Wl,-rpath,\$ORIGIN"
	    -Wl,--enable-new-dtags ${H_LDFLAGS} "${GEN}/crtbegin_dynamic.o")
	target_link_libraries(${name} PRIVATE ${H_LIBS} ${LIBCXX_STATIC}
	    c_shared dl_shared "${GEN}/crtend.o")
	if(BUILTINS_LIB)
		target_link_libraries(${name} PRIVATE "${BUILTINS_LIB}")
	endif()
endfunction()
bionic_test_helper(elftls_align_test_helper)
bionic_test_helper(elftls_dlopen_ie_error_helper LDFLAGS
    "-Wl,-rpath,\$ORIGIN/..")
bionic_test_helper(elftls_dtv_resize_helper INCLUDES "${LIBC}")
bionic_test_helper(elftls_skew_align_test_helper)
bionic_test_helper(ns_hidden_child_helper INCLUDES "${LIBC}" LIBS
    libns_hidden_child_internal libns_hidden_child_global dl_android
    LDFLAGS "-Wl,-rpath,\$ORIGIN/..")

add_executable(bionic-unit-tests-static $<TARGET_OBJECTS:bionic_test_objs>)
add_dependencies(bionic-unit-tests-static crt)
target_link_options(bionic-unit-tests-static PRIVATE -static -nostdlib
    -fuse-ld=lld -Wl,--gc-sections "${GEN}/crtbegin_static.o")
target_link_libraries(bionic-unit-tests-static PRIVATE ${BIONIC_TEST_LIBS}
    libtest_elftls_shared_var_static libtest_elftls_tprel_static c_static
    "${GEN}/crtend.o")
set_target_properties(bionic-unit-tests-static PROPERTIES
    LINK_DEPENDS "${GEN}/crtbegin_static.o")

# As in bionic_unit_tests_defaults: PIE, --export-dynamic, libc++ static,
# DT_RUNPATH $ORIGIN/bionic-loader-test-libs.
add_executable(bionic-unit-tests $<TARGET_OBJECTS:bionic_test_objs>
    $<TARGET_OBJECTS:bionic_loader_test_objs>)
add_dependencies(bionic-unit-tests crt)
target_link_options(bionic-unit-tests PRIVATE -nostdlib -fuse-ld=lld -pie
    -Wl,--dynamic-linker=/system/bin/linker64 -Wl,--export-dynamic
    -Wl,--gc-sections "-Wl,-rpath,\$ORIGIN/bionic-loader-test-libs"
    -Wl,--enable-new-dtags "${GEN}/crtbegin_dynamic.o")
target_link_libraries(bionic-unit-tests PRIVATE ziparchive z
    ${BIONIC_TEST_LIBS} c_shared ld_android dl_shared dl_android
    libdl_test_df_1_global
    libtest_elftls_shared_var libtest_elftls_tprel "${GEN}/crtend.o")
set_target_properties(bionic-unit-tests PROPERTIES SKIP_BUILD_RPATH ON
    LINK_DEPENDS "${GEN}/crtbegin_dynamic.o")

if(BUILTINS_LIB)
	target_link_libraries(bionic-unit-tests-static PRIVATE "${BUILTINS_LIB}")
	target_link_libraries(bionic-unit-tests PRIVATE "${BUILTINS_LIB}")
endif()

# propd makes the property area of the jail and answers
# __system_property_set(), as init does on a device.  It is static, so the
# jail can start it before anything else.
set(PROPSVC "${AOSP_SYSTEM}/core/property_service")
aosp_library(propertyinfoserializer
    SRCS "${PROPSVC}/libpropertyinfoserializer/property_info_file.cpp"
        "${PROPSVC}/libpropertyinfoserializer/property_info_serializer.cpp"
        "${PROPSVC}/libpropertyinfoserializer/trie_builder.cpp"
        "${PROPSVC}/libpropertyinfoserializer/trie_serializer.cpp"
    FLAGS -std=gnu++20 -Wall -Wextra -Werror
    INCLUDES "${PROPSVC}/libpropertyinfoserializer/include"
        "${PROPINFO}/include" "${LIBBASE}/include")
set(PROPD "${PROJECT_ROOT}/aosp/jail/propd")
add_executable(propd "${PROPD}/propd.cpp")
add_dependencies(propd crt)
target_include_directories(propd SYSTEM BEFORE PRIVATE
    "${CXX_INCLUDE}")
target_include_directories(propd PRIVATE
    "${PROPSVC}/libpropertyinfoserializer/include" "${LIBBASE}/include"
    "${AOSP_SYSTEM}/core/libcutils/include")
target_compile_options(propd PRIVATE -std=gnu++20 -Wall -Wextra
    -Werror ${AOSP_CXX_FLAGS})
target_link_options(propd PRIVATE -static -nostdlib -fuse-ld=lld
    -Wl,--gc-sections "${GEN}/crtbegin_static.o")
target_link_libraries(propd PRIVATE -Wl,--start-group
    propertyinfoserializer base log ${LIBCXX_STATIC} -Wl,--end-group
    c_static "${GEN}/crtend.o")
set_target_properties(propd PROPERTIES
    LINK_DEPENDS "${GEN}/crtbegin_static.o")
if(BUILTINS_LIB)
	target_link_libraries(propd PRIVATE "${BUILTINS_LIB}")
endif()
configure_file("${PROPD}/property_contexts" property_contexts COPYONLY)

# propwait_test: a client with the read-only area waits for a property that
# another process sets through propd.  With -s, six clients wait at
# the same time.
add_executable(propwait_test
    "${PROJECT_ROOT}/aosp/jail/propwait_test/propwait_test.cpp")
add_dependencies(propwait_test crt)
target_include_directories(propwait_test SYSTEM BEFORE PRIVATE
    "${CXX_INCLUDE}")
target_compile_options(propwait_test PRIVATE -std=gnu++20 -Wall -Wextra
    -Werror ${AOSP_CXX_FLAGS})
target_link_options(propwait_test PRIVATE -static -nostdlib -fuse-ld=lld
    -Wl,--gc-sections "${GEN}/crtbegin_static.o")
target_link_libraries(propwait_test PRIVATE ${LIBCXX_STATIC} c_static
    "${GEN}/crtend.o")
set_target_properties(propwait_test PROPERTIES
    LINK_DEPENDS "${GEN}/crtbegin_static.o")
if(BUILTINS_LIB)
	target_link_libraries(propwait_test PRIVATE "${BUILTINS_LIB}")
endif()

# pthread_stress: six threads, then six processes, on mutexes, condition
# variables and rwlocks.
add_executable(pthread_stress
    "${PROJECT_ROOT}/aosp/jail/pthread_stress/pthread_stress.cpp")
add_dependencies(pthread_stress crt)
target_include_directories(pthread_stress SYSTEM BEFORE PRIVATE
    "${CXX_INCLUDE}")
target_compile_options(pthread_stress PRIVATE -std=gnu++20 -Wall -Wextra
    -Werror ${AOSP_CXX_FLAGS})
target_link_options(pthread_stress PRIVATE -static -nostdlib -fuse-ld=lld
    -Wl,--gc-sections "${GEN}/crtbegin_static.o")
target_link_libraries(pthread_stress PRIVATE ${LIBCXX_STATIC} c_static
    "${GEN}/crtend.o")
set_target_properties(pthread_stress PROPERTIES
    LINK_DEPENDS "${GEN}/crtbegin_static.o")
if(BUILTINS_LIB)
	target_link_libraries(pthread_stress PRIVATE "${BUILTINS_LIB}")
endif()

# The rest of the Android root: libm, ICU's libicuuc, sh, liblog,
# libnativehelper and the build-time properties.
include(android-root.cmake)

# Both suites run in a jail whose root is the Android root, where
# /system/bin/linker64 exists.  The jail mounts host directories under that
# root, so it must not be "/".
set(ANDROID_JAIL_ROOT "/android/root" CACHE PATH
    "Android root of the bionic_tests jail")
if(NOT ANDROID_JAIL_ROOT MATCHES "^/[^/]")
	message(FATAL_ERROR "ANDROID_JAIL_ROOT must be an absolute path, not /")
endif()
configure_file(bionic-tests-jail.conf.in bionic-tests-jail.conf @ONLY)

# run-gtest-suite.sh runs each test in its own process.  The arguments
# after the exclusion list are the command that runs the suite.
set(RUN_SUITE sh "${CMAKE_CURRENT_SOURCE_DIR}/run-gtest-suite.sh")
# Each suite goes to the jail with the test libraries and helper programs.
# TEST_BIN is last in PATH, after the directories of the host or the jail.
set(RUN_SUITE_PATH "PATH=/sbin:/bin:/usr/sbin:/usr/bin:${TEST_BIN}")
add_test(NAME bionic_unit_tests_static COMMAND ${RUN_SUITE}
    -j "${GEN}/bionic-tests-jail.conf" -d "${TESTLIB_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/bionic-unit-tests-static.excluded"
    "$<TARGET_FILE:bionic-unit-tests-static>")
set_tests_properties(bionic_unit_tests_static PROPERTIES
    ENVIRONMENT "${RUN_SUITE_PATH}")
add_test(NAME bionic_unit_tests COMMAND ${RUN_SUITE}
    -j "${GEN}/bionic-tests-jail.conf" -d "${TESTLIB_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/bionic-unit-tests.excluded"
    "$<TARGET_FILE:linker64>" "$<TARGET_FILE:bionic-unit-tests>")
set_tests_properties(bionic_unit_tests PROPERTIES
    ENVIRONMENT "LD_LIBRARY_PATH=${GEN};${RUN_SUITE_PATH}")
add_test(NAME property_wait_read_only COMMAND sh
    "${CMAKE_CURRENT_SOURCE_DIR}/run-in-jail.sh"
    "${GEN}/bionic-tests-jail.conf" "$<TARGET_FILE:propwait_test>")
set_tests_properties(property_wait_read_only PROPERTIES SKIP_RETURN_CODE 77)
# Six readers wait at the same time while three setters change properties,
# 100 iterations.
add_test(NAME property_wait_stress COMMAND sh
    "${CMAKE_CURRENT_SOURCE_DIR}/run-in-jail.sh"
    "${GEN}/bionic-tests-jail.conf" "$<TARGET_FILE:propwait_test>" -s 100)
set_tests_properties(property_wait_stress PROPERTIES SKIP_RETURN_CODE 77)
# Mutex, condition variable and rwlock stress, 100 iterations.
add_test(NAME pthread_stress COMMAND sh
    "${CMAKE_CURRENT_SOURCE_DIR}/run-in-jail.sh"
    "${GEN}/bionic-tests-jail.conf" "$<TARGET_FILE:pthread_stress>" 100)
set_tests_properties(pthread_stress PROPERTIES SKIP_RETURN_CODE 77)
