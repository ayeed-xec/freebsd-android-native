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
# The Android root beyond libc, libdl and linker64, built from AOSP sources
# with the flags of their Android.bp files:
#
#   /apex/com.android.runtime/lib64/bionic/libm.so   libm, linked from
#                                      /system/lib64
#   /apex/com.android.i18n/lib64/libicuuc.so    ICU's libicuuc
#   /apex/com.android.i18n/lib64/libicui18n.so  ICU's libicui18n
#   /system/bin/sh                     mksh, the sh module of external/mksh
#   /system/bin/toybox                 toybox and its links (toybox.cmake)
#   /system/etc/mkshrc                 its startup file
#   /system/build.prop                 the build-time properties
#   /system/lib64/liblog.so            liblog
#   /system/lib64/libnativehelper.so   libnativehelper
#   /system/lib64/libz.so              zlib, the libz module of external/zlib
#   /system/lib64/libcrypto.so         BoringSSL's libcrypto, FIPS
#                                      (boringssl.cmake)
#   /system/lib64/libselinux.so        libselinux, SELinux disabled
#   /system/lib64/libpcre2.so          pcre2, for libselinux
#   /system/lib64/libpackagelistparser.so
#                                      for libselinux (selinux.cmake)
#
# On a device libnativehelper.so is in the ART APEX, and the linker
# configuration makes it visible to the system namespace.  There is no
# linker configuration here, so the system namespace searches only
# /system/lib64.

set(AOSP_NATIVEHELPER "/home/dev/aosp/libnativehelper" CACHE PATH
    "AOSP libnativehelper checkout at the pinned build")
set(MKSH "${AOSP_EXTERNAL}/mksh")
set(ICU "${AOSP_EXTERNAL}/icu")
set(NATIVEHELPER "${AOSP_NATIVEHELPER}")
foreach(f "${MKSH}/src/main.c" "${ICU}/icu4c/source/common/putil.cpp"
    "${ICU}/icu4c/source/i18n/ucol.cpp" "${NATIVEHELPER}/JNIHelp.c")
	if(NOT EXISTS "${f}")
		message(FATAL_ERROR "${f} is missing; run aosp/fetch.sh "
		    "--project platform/external/mksh --project "
		    "platform/external/icu:icu4c/source/common,"
		    "icu4c/source/i18n,icu4c/source/stubdata,"
		    "libandroidicuinit,android_icu4c "
		    "--project platform/libnativehelper")
	endif()
endforeach()

# libm.so: the libm module of libm/Android.bp for arm64, with
# libarm-optimized-routines-math in it.  As libc.so, it has no version
# script yet: Android makes libm.arm64.map with bionic's
# generate-version-script.
set(LIBM "${BIONIC_SRC}/libm")
set(MSUN "${LIBM}/upstream-freebsd/lib/msun")
set(LIBM_MSUN_SRCS catrig catrigf e_acos e_acosf e_acosh e_acoshf e_asin
    e_asinf e_atan2 e_atan2f e_atanh e_atanhf e_cosh e_coshf e_fmod e_fmodf
    e_gamma e_gammaf e_gammaf_r e_gamma_r e_hypot e_hypotf e_j0 e_j0f e_j1
    e_j1f e_jn e_jnf e_lgamma e_lgammaf e_lgammaf_r e_lgamma_r e_log10
    e_log10f e_remainder e_remainderf e_rem_pio2 e_rem_pio2f e_scalb e_scalbf
    e_sinh e_sinhf k_cos k_cosf k_exp k_expf k_rem_pio2 k_sin k_sinf k_tan
    k_tanf s_asinh s_asinhf s_atan s_atanf s_carg s_cargf s_cargl s_cbrt
    s_cbrtf s_ccosh s_ccoshf s_cexp s_cexpf s_cimag s_cimagf s_cimagl s_clog
    s_clogf s_conj s_conjf s_conjl s_cos s_cospi s_cpow s_cpowf s_cpowl
    s_cproj s_cprojf s_cprojl s_creal s_crealf s_creall s_csinh s_csinhf
    s_csqrt s_csqrtf s_ctanh s_ctanhf s_erf s_erff s_expm1 s_expm1f s_fdim
    s_finite s_finitef s_frexp s_frexpf s_ilogb s_ilogbf s_log1p s_log1pf
    s_logb s_logbf s_modf s_modff s_nan s_nearbyint s_nextafter s_nextafterf
    s_remquo s_remquof s_scalbln s_scalbn s_scalbnf s_signgam s_significand
    s_significandf s_sin s_sinpi s_sincos s_tan s_tanf s_tanh s_tanhf
    s_tgammaf w_cabs w_cabsf w_cabsl w_drem w_dremf
    # libm_lp64_sources
    catrigl e_acosl e_acoshl e_asinl e_atan2l e_atanhl e_fmodl e_hypotl
    e_lgammal e_remainderl e_sqrtl s_asinhl s_atanl s_cbrtl s_ceill s_clogl
    e_coshl s_cosl s_csqrtl s_floorl s_fmal s_fmaxl s_fminl s_modfl s_frexpl
    s_ilogbl s_llrintl s_llroundl s_logbl s_lrintl s_lroundl s_nextafterl
    s_nexttoward s_nexttowardf s_remquol s_rintl s_roundl s_scalbnl
    s_sincosl e_sinhl s_sinl s_tanhl s_tanl s_truncl)
list(TRANSFORM LIBM_MSUN_SRCS PREPEND "${MSUN}/src/")
set(LIBM_LD128_SRCS invtrig e_lgammal_r e_powl k_cosl k_sinl k_tanl s_erfl
    s_exp2l s_expl s_logl s_nanl)
list(TRANSFORM LIBM_LD128_SRCS PREPEND "${MSUN}/ld128/")
set(LIBM_NETBSD_SRCS ccoshl ccosl cephes_subrl cexpl csinhl csinl ctanhl
    ctanl)
list(TRANSFORM LIBM_NETBSD_SRCS PREPEND
    "${LIBM}/upstream-netbsd/lib/libm/complex/")
set(LIBM_SRCS "${MSUN}/bsdsrc/b_tgamma" ${LIBM_MSUN_SRCS} ${LIBM_LD128_SRCS}
    ${LIBM_NETBSD_SRCS} "${LIBM}/significandl" "${LIBM}/fake_long_double"
    "${LIBM}/fenv-arm64")
list(TRANSFORM LIBM_SRCS APPEND ".c")
add_library(aor_math OBJECT ${AOR_MATH_SRCS})
target_include_directories(aor_math PRIVATE "${AOR_MATH}/include")
target_compile_options(aor_math PRIVATE -Wno-undef -Wno-unused-parameter -O2
    -ffp-contract=fast -fno-math-errno -D__BIONIC_LP32_USE_LONG_DOUBLE
    -DFLT_EVAL_METHOD=0 -DWANT_ERRNO=0 -DWANT_VMATH=0 -DWANT_SIMD_TESTS=0
    -DWANT_EXP10_TESTS=0 -DWANT_MOPS=1 -DHAVE_FAST_FMA=1)
add_library(m_shared SHARED ${LIBM_SRCS} "${LIBM}/builtins.cpp"
    "${LIBM}/signbit.cpp" $<TARGET_OBJECTS:aor_math>)
add_dependencies(m_shared crt)
set_target_properties(m_shared PROPERTIES OUTPUT_NAME m SKIP_BUILD_RPATH ON
    LINK_DEPENDS "${GEN}/crtbegin_so.o")
target_include_directories(m_shared PRIVATE
    "${LIBM}/upstream-freebsd/android/include" "${MSUN}/src" "${MSUN}/ld128"
    "${LIBM}" "${LIBC}")
# -Wno-undef: the -Wundef of our clang configuration, which AOSP's clang
# does not have.
target_compile_options(m_shared PRIVATE -include freebsd-compat.h
    -fno-builtin -fno-math-errno -Wno-missing-braces -Wno-parentheses
    -Wno-sign-compare -Wno-static-in-inline -Wno-unknown-pragmas
    -Wno-unused-const-variable -Wno-unused-variable -Wno-undef)
target_link_options(m_shared PRIVATE ${SO_LINK_OPTIONS} -Wl,-soname,libm.so
    -Wl,--Bsymbolic-functions "${GEN}/crtbegin_so.o")
target_link_libraries(m_shared PRIVATE c_shared "${GEN}/crtend_so.o")
if(BUILTINS_LIB)
	target_link_libraries(m_shared PRIVATE "${BUILTINS_LIB}")
endif()

# A program of the system partition: PIE, PT_INTERP /system/bin/linker64.
function(system_program name)
	cmake_parse_arguments(P "" "" "SRCS;LIBS" ${ARGN})
	add_executable(${name} ${P_SRCS})
	add_dependencies(${name} crt)
	set_target_properties(${name} PROPERTIES SKIP_BUILD_RPATH ON
	    LINK_DEPENDS "${GEN}/crtbegin_dynamic.o")
	target_link_options(${name} PRIVATE -nostdlib -fuse-ld=lld -pie
	    -Wl,--dynamic-linker=/system/bin/linker64 -Wl,--gc-sections
	    "${GEN}/crtbegin_dynamic.o")
	target_link_libraries(${name} PRIVATE ${P_LIBS} c_shared m_shared
	    dl_shared "${GEN}/crtend.o")
	if(BUILTINS_LIB)
		target_link_libraries(${name} PRIVATE "${BUILTINS_LIB}")
	endif()
endfunction()

# A shared library of the system partition, linked as Soong links one.
function(system_library name)
	cmake_parse_arguments(L "" "SONAME;MAP" "SRCS;LIBS" ${ARGN})
	add_library(${name} SHARED ${L_SRCS})
	add_dependencies(${name} crt)
	set_target_properties(${name} PROPERTIES PREFIX "" NO_SONAME ON
	    SKIP_BUILD_RPATH ON LINK_DEPENDS "${GEN}/crtbegin_so.o")
	target_link_options(${name} PRIVATE ${SO_LINK_OPTIONS}
	    "-Wl,-soname,${L_SONAME}" "${GEN}/crtbegin_so.o")
	if(L_MAP)
		target_link_options(${name} PRIVATE
		    "-Wl,--version-script=${L_MAP}")
	endif()
	target_link_libraries(${name} PRIVATE ${L_LIBS} c_shared m_shared
	    dl_shared "${GEN}/crtend_so.o")
	if(BUILTINS_LIB)
		target_link_libraries(${name} PRIVATE "${BUILTINS_LIB}")
	endif()
endfunction()

# mksh: mksh_defaults and the android target of external/mksh/Android.bp.
# The target name is not "sh": add_test() would then run this program in
# place of the host's sh.
set(MKSH_SRCS lalloc edit eval exec expr funcs histrap jobs lex main misc
    shf syn tree ulimit var)
list(TRANSFORM MKSH_SRCS PREPEND "${MKSH}/src/")
list(TRANSFORM MKSH_SRCS APPEND ".c")
system_program(mksh SRCS ${MKSH_SRCS})
target_include_directories(mksh PRIVATE "${MKSH}/src")
target_compile_options(mksh PRIVATE -Wall -Werror
    -Wno-deprecated-declarations -fno-asynchronous-unwind-tables
    -fno-strict-aliasing -fwrapv
    -DDEBUG_LEAKS -DMKSH_ASSUME_UTF8 -DMKSH_DONT_EMIT_IDSTRING
    "-DKSH_VERSIONNAME_VENDOR_EXT=\" Android\""
    -DMKSH_BUILDSH -D_GNU_SOURCE -DSETUID_CAN_FAIL_WITH_EAGAIN
    -DHAVE_STRING_POOLING=2 -DHAVE_ATTRIBUTE_BOUNDED=1
    -DHAVE_ATTRIBUTE_FORMAT=1 -DHAVE_ATTRIBUTE_NORETURN=1
    -DHAVE_ATTRIBUTE_PURE=1 -DHAVE_ATTRIBUTE_UNUSED=1
    -DHAVE_ATTRIBUTE_USED=1 -DHAVE_SYS_TIME_H=1 -DHAVE_TIME_H=1
    -DHAVE_BOTH_TIME_H=1 -DHAVE_SYS_BSDTYPES_H=0 -DHAVE_SYS_FILE_H=1
    -DHAVE_SYS_MKDEV_H=0 -DHAVE_SYS_MMAN_H=1 -DHAVE_SYS_PARAM_H=1
    -DHAVE_SYS_RESOURCE_H=1 -DHAVE_SYS_SELECT_H=1 -DHAVE_SYS_SYSMACROS_H=1
    -DHAVE_BSTRING_H=0 -DHAVE_GRP_H=1 -DHAVE_IO_H=0 -DHAVE_LIBGEN_H=1
    -DHAVE_LIBUTIL_H=0 -DHAVE_PATHS_H=1 -DHAVE_STDINT_H=1
    -DHAVE_STRINGS_H=1 -DHAVE_TERMIOS_H=1 -DHAVE_ULIMIT_H=0
    -DHAVE_VALUES_H=0 -DHAVE_CAN_INTTYPES=1 -DHAVE_CAN_UCBINTS=1
    -DHAVE_CAN_INT8TYPE=1 -DHAVE_CAN_UCBINT8=1 -DHAVE_SIG_T=1
    -DHAVE_SYS_ERRLIST=0 -DHAVE_SYS_SIGNAME=1 -DHAVE_SYS_SIGLIST=1
    -DHAVE_FLOCK=1 -DHAVE_LOCK_FCNTL=1 -DHAVE_RLIMIT=1 -DHAVE_RLIM_T=1
    -DHAVE_GETRUSAGE=1 -DHAVE_GETSID=1 -DHAVE_GETTIMEOFDAY=1
    -DHAVE_KILLPG=1 -DHAVE_MEMMOVE=1 -DHAVE_MKNOD=0 -DHAVE_MMAP=1
    -DHAVE_FTRUNCATE=1 -DHAVE_NICE=1 -DHAVE_REVOKE=0
    -DHAVE_SETLOCALE_CTYPE=1 -DHAVE_LANGINFO_CODESET=1 -DHAVE_SELECT=1
    -DHAVE_SETRESUGID=1 -DHAVE_SETGROUPS=1 -DHAVE_STRERROR=1
    -DHAVE_STRSIGNAL=1 -DHAVE_STRLCPY=1 -DHAVE_FLOCK_DECL=1
    -DHAVE_REVOKE_DECL=1 -DHAVE_SYS_ERRLIST_DECL=0
    -DHAVE_SYS_SIGLIST_DECL=1 -DHAVE_ST_MTIM=1 -DHAVE_ST_MTIMENSEC=0
    -DHAVE_PERSISTENT_HISTORY=0 -DMKSH_BUILD_R=593
    "-DMKSH_DEFAULT_PROFILEDIR=\"/system/etc\""
    "-DMKSHRC_PATH=\"/system/etc/mkshrc\""
    "-DMKSH_DEFAULT_EXECSHELL=\"/system/bin/sh\""
    "-DMKSH_DEFAULT_TMPDIR=\"/data/local\"")

# liblog.so: the liblog module of liblog/Android.bp, with the sources and
# the version script of the android target.  Android links it against
# libc++.so; the bionic sysroot has only the static libc++, so it is linked
# in, and the version script keeps its symbols local.
set(LIBLOG_SRCS log_event_list.cpp log_event_write.cpp logger_name.cpp
    logger_read.cpp logger_write.cpp logprint.cpp properties.cpp
    event_tag_map.cpp log_time.cpp pmsg_reader.cpp pmsg_writer.cpp
    logd_reader.cpp logd_writer.cpp)
list(TRANSFORM LIBLOG_SRCS PREPEND "${LIBLOG}/")
system_library(log_shared SONAME liblog.so MAP "${LIBLOG}/liblog.map.txt"
    SRCS ${LIBLOG_SRCS} LIBS ${LIBCXX_STATIC})
set_target_properties(log_shared PROPERTIES OUTPUT_NAME liblog)
target_include_directories(log_shared SYSTEM BEFORE PRIVATE "${CXX_INCLUDE}")
target_include_directories(log_shared PRIVATE "${LIBLOG}/include"
    "${LIBBASE}/include" "${AOSP_SYSTEM}/core/libcutils/include"
    "${AOSP_SYSTEM}/core/libutils/include"
    "${AOSP_SYSTEM}/core/libsystem/include")
target_compile_options(log_shared PRIVATE -std=gnu++20 -D_FILE_OFFSET_BITS=64
    -DNDEBUG ${AOSP_CXX_FLAGS} -Wexit-time-destructors -DLIBLOG_LOG_TAG=1006
    -DSNET_EVENT_LOG_TAG=1397638484 -DANDROID_DEBUGGABLE=0)

# libz.so: the libz module of external/zlib, from the objects of zlib.cmake.
# It has no version script: libz.map.txt is the symbol file of the NDK stub
# library only.
system_library(z_shared SONAME libz.so SRCS $<TARGET_OBJECTS:zlib_objects>)
set_target_properties(z_shared PROPERTIES OUTPUT_NAME libz)

# libnativehelper.so: libnativehelper with libnativehelper_any_vm in it.
# It is C (stl: "none") and needs only liblog.
set(NATIVEHELPER_SRCS DlHelp.c ExpandableString.c JNIHelp.c JniInvocation.c
    JNIPlatformHelp.c JniConstants.c file_descriptor_jni.c)
list(TRANSFORM NATIVEHELPER_SRCS PREPEND "${NATIVEHELPER}/")
system_library(nativehelper SONAME libnativehelper.so
    SRCS ${NATIVEHELPER_SRCS} LIBS log_shared)
set_target_properties(nativehelper PROPERTIES OUTPUT_NAME libnativehelper)
target_include_directories(nativehelper PRIVATE
    "${NATIVEHELPER}/header_only_include" "${NATIVEHELPER}/include"
    "${NATIVEHELPER}/include_jni" "${NATIVEHELPER}/include_platform"
    "${NATIVEHELPER}/include_platform_header_only" "${LIBLOG}/include")
target_compile_options(nativehelper PRIVATE -fvisibility=protected -std=c11)

# libicuuc.so: libicuuc of icu4c/source/common/Android.bp, with
# libandroidicuinit and libicuuc_stubdata in it.  On a device it needs
# libc++.so and libbase.so.  The bionic sysroot has only the static libc++,
# and tier 0 builds only the static libbase, so both are linked in, and
# --exclude-libs keeps their symbols local.
set(ICU4C "${ICU}/icu4c/source")
set(ICU_INCLUDES "${ICU4C}/common" "${ICU}/android_icu4c/include")
add_library(icu_androidicuinit OBJECT
    "${ICU}/libandroidicuinit/IcuRegistration.cpp"
    "${ICU}/libandroidicuinit/android_icu_init.cpp")
add_library(icu_stubdata OBJECT "${ICU4C}/stubdata/stubdata.cpp")
foreach(objs icu_androidicuinit icu_stubdata)
	target_include_directories(${objs} SYSTEM BEFORE PRIVATE
	    "${CXX_INCLUDE}")
	target_include_directories(${objs} PRIVATE ${ICU_INCLUDES}
	    "${ICU}/libandroidicuinit/include" "${LIBBASE}/include"
	    "${LIBLOG}/include")
	target_compile_options(${objs} PRIVATE -std=gnu++20 ${AOSP_CXX_FLAGS}
	    -DANDROID_LINK_SHARED_ICU4C)
endforeach()
# Android.bp builds "*.cpp" of icu4c/source/common.
file(GLOB ICU_UC_SRCS "${ICU4C}/common/*.cpp")
system_library(icuuc SONAME libicuuc.so
    SRCS ${ICU_UC_SRCS} $<TARGET_OBJECTS:icu_androidicuinit>
        $<TARGET_OBJECTS:icu_stubdata>
    LIBS log_shared base ${LIBCXX_STATIC})
set_target_properties(icuuc PROPERTIES OUTPUT_NAME libicuuc)
# icu4c_defaults, with rtti: true.
set(ICU4C_FLAGS -std=gnu++20 ${AOSP_CXX_FLAGS} -frtti
    -Wno-ambiguous-reversed-operator -Wno-deprecated-declarations
    -Wno-unused-parameter -Wno-unused-const-variable
    -Wno-unneeded-internal-declaration -Wno-unnecessary-virtual-specifier
    -DUCONFIG_USE_ML_PHRASE_BREAKING=1 -DANDROID_LINK_SHARED_ICU4C)
target_include_directories(icuuc SYSTEM BEFORE PRIVATE "${CXX_INCLUDE}")
target_include_directories(icuuc PRIVATE ${ICU_INCLUDES})
target_compile_options(icuuc PRIVATE ${ICU4C_FLAGS} -D_REENTRANT
    -DU_COMMON_IMPLEMENTATION -O3 -fvisibility=hidden
    -Wno-missing-field-initializers -Wno-sign-compare -DPIC)
target_link_options(icuuc PRIVATE -Wl,--exclude-libs,ALL)

# libicui18n.so: libicui18n of icu4c/source/i18n/Android.bp, on top of
# libicuuc.so.  It also links the static libc++.
file(GLOB ICU_I18N_SRCS "${ICU4C}/i18n/*.cpp")
system_library(icui18n SONAME libicui18n.so SRCS ${ICU_I18N_SRCS}
    LIBS icuuc ${LIBCXX_STATIC})
set_target_properties(icui18n PROPERTIES OUTPUT_NAME libicui18n)
target_include_directories(icui18n SYSTEM BEFORE PRIVATE "${CXX_INCLUDE}")
target_include_directories(icui18n PRIVATE "${ICU4C}/i18n" ${ICU_INCLUDES})
target_compile_options(icui18n PRIVATE ${ICU4C_FLAGS} -D_REENTRANT
    -DU_I18N_IMPLEMENTATION -O3 -fvisibility=hidden
    -Wno-unreachable-code-loop-increment -DPIC)
target_link_options(icui18n PRIVATE -Wl,--exclude-libs,ALL)

# The files go in <build>/android-root next to the bionic files of the
# android_root target.  libm.so is a bootstrap library of the runtime APEX,
# as libc.so is, so /system/lib64 links to it.
set(ROOT "${GEN}/android-root")
set(RUNTIME_LIB "/apex/com.android.runtime/lib64/bionic")
add_custom_target(android_root_platform ALL
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${ROOT}${RUNTIME_LIB}"
        "${ROOT}/apex/com.android.i18n/lib64" "${ROOT}/system/bin"
        "${ROOT}/system/etc" "${ROOT}/system/lib64"
    COMMAND "${CMAKE_COMMAND}" -E copy $<TARGET_FILE:m_shared>
        "${ROOT}${RUNTIME_LIB}/libm.so"
    COMMAND "${CMAKE_COMMAND}" -E create_symlink "${RUNTIME_LIB}/libm.so"
        "${ROOT}/system/lib64/libm.so"
    COMMAND "${CMAKE_COMMAND}" -E copy $<TARGET_FILE:icuuc>
        $<TARGET_FILE:icui18n> "${ROOT}/apex/com.android.i18n/lib64"
    COMMAND "${CMAKE_COMMAND}" -E copy $<TARGET_FILE:mksh>
        "${ROOT}/system/bin/sh"
    COMMAND "${CMAKE_COMMAND}" -E copy "${MKSH}/mkshrc"
        "${ROOT}/system/etc/mkshrc"
    COMMAND "${CMAKE_COMMAND}" -E copy
        "${AOSP_SYSTEM}/core/rootdir/etc/hosts" "${ROOT}/system/etc/hosts"
    COMMAND "${CMAKE_COMMAND}" -E copy "${PROJECT_ROOT}/aosp/jail/build.prop"
        "${ROOT}/system/build.prop"
    COMMAND "${CMAKE_COMMAND}" -E copy $<TARGET_FILE:log_shared>
        $<TARGET_FILE:nativehelper> $<TARGET_FILE:z_shared>
        "${GEN}/libcrypto.so" $<TARGET_FILE:selinux_shared>
        $<TARGET_FILE:pcre2_shared> $<TARGET_FILE:packagelistparser_shared>
        "${ROOT}/system/lib64"
    DEPENDS m_shared icuuc icui18n mksh log_shared nativehelper z_shared
        "${GEN}/libcrypto.so" selinux_shared pcre2_shared
        packagelistparser_shared
        "${MKSH}/mkshrc" "${PROJECT_ROOT}/aosp/jail/build.prop"
        "${AOSP_SYSTEM}/core/rootdir/etc/hosts"
    VERBATIM)
add_dependencies(android_root_platform android_root)
