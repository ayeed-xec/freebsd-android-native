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
# logd, logcat, logwrapper and the libraries that they need, with the
# sources and flags of their Android.bp files: zstd, libcap, jsoncpp,
# libsysutils, libpackagelistparser, libprocessgroup, libaudit, liblogd,
# abseil and libprotobuf-cpp-lite.  The programs go to /system/bin of the
# Android root, with /system/etc/event-log-tags, cgroups.json and
# task_profiles.json.
# svcstart starts logd in the jail with the lines of logd.rc.
#
# Differences from the Android build:
# - logd is built with LOGD_NO_BINDER: libbinder is not built yet.
# - libsysutils has no NetlinkListener and NetlinkEvent: they need the
#   uevent headers.
# - cgroups.json has no controllers, because FreeBSD has no cgroups.
#   libprocessgroup then drops the cgroup actions of the task profiles.
# - task_profiles.json is the file of libprocessgroup without its
#   SetTimerSlack actions: FreeBSD has no timer slack for a thread.
#
# The global flags have -Werror.  Soong stops on a warning only for the
# modules that have -Werror in their Android.bp, so the others get
# -Wno-error here.

set(ZSTD "${AOSP_EXTERNAL}/zstd")
set(LIBCAP "${AOSP_EXTERNAL}/libcap")
set(JSONCPP "${AOSP_EXTERNAL}/jsoncpp")
set(LIBSYSUTILS "${AOSP_SYSTEM}/core/libsysutils")
set(PKGLIST "${AOSP_SYSTEM}/core/libpackagelistparser")
set(PROCESSGROUP "${AOSP_SYSTEM}/core/libprocessgroup")
set(LOGD "${AOSP_SYSTEM}/logging/logd")
set(LOGWRAPPER "${AOSP_SYSTEM}/logging/logwrapper")
foreach(f "${ZSTD}/lib/zstd.h" "${LIBCAP}/libcap/cap_proc.c"
    "${JSONCPP}/src/lib_json/json_value.cpp"
    "${AOSP_EXTERNAL}/abseil-cpp/absl/base/config.h"
    "${AOSP_EXTERNAL}/protobuf/upb_generator/common.cc")
	if(NOT EXISTS "${f}")
		message(FATAL_ERROR "${f} is missing; run aosp/fetch.sh "
		    "--project platform/external/zstd --project "
		    "platform/external/libcap --project platform/external/jsoncpp "
		    "--project platform/external/abseil-cpp --project "
		    "platform/external/protobuf:src,cmake,upb,upb_generator,"
		    "editions,third_party")
	endif()
endforeach()
foreach(f "${LIBSYSUTILS}/src/SocketListener.cpp"
    "${PKGLIST}/packagelistparser.cpp" "${LOGWRAPPER}/logwrapper.cpp")
	if(NOT EXISTS "${f}")
		message(FATAL_ERROR "${f} is missing; add libsysutils and "
		    "libpackagelistparser to the sparse checkout of system/core, "
		    "and logwrapper to the one of system/logging")
	endif()
endforeach()

# zstd: libzstd and zstd_defaults.
file(GLOB ZSTD_SRCS "${ZSTD}/lib/*/*.c")
aosp_library(zstd
    SRCS ${ZSTD_SRCS}
    FLAGS -DZSTD_HAVE_WEAK_SYMBOLS=0 -DZSTD_TRACE=0 -Wno-error
    INCLUDES "${ZSTD}/lib/common" "${ZSTD}/lib")

# libcap.  cap_names.h comes from _makenames, a build host program, and the
# capability names of linux-compat <linux/capability.h>.
set(CAP_GEN "${GEN}/libcap")
add_custom_command(OUTPUT "${CAP_GEN}/cap_names.h"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${CAP_GEN}"
    COMMAND "${AWK}" -f "${LIBCAP}/generate_cap_names_list.awk"
        "${LIBC}/include/linux-compat/linux/capability.h"
        > "${CAP_GEN}/cap_names.list.h"
    COMMAND "${HOST_CC}" -Wall -I "${CAP_GEN}" -o "${CAP_GEN}/_makenames"
        "${LIBCAP}/libcap/_makenames.c"
    COMMAND "${CAP_GEN}/_makenames" > "${CAP_GEN}/cap_names.h"
    DEPENDS "${LIBCAP}/generate_cap_names_list.awk"
        "${LIBC}/include/linux-compat/linux/capability.h"
        "${LIBCAP}/libcap/_makenames.c"
    VERBATIM)
set(LIBCAP_SRCS cap_alloc.c cap_extint.c cap_file.c cap_flag.c cap_proc.c
    cap_text.c)
list(TRANSFORM LIBCAP_SRCS PREPEND "${LIBCAP}/libcap/")
aosp_library(cap
    SRCS ${LIBCAP_SRCS} "${CAP_GEN}/cap_names.h"
    FLAGS -Wno-pointer-arith -Wno-tautological-compare
        -Wno-unused-parameter -Wno-unused-result -Wno-unused-variable
        -Wno-error
    INCLUDES "${LIBCAP}/libcap/include" "${CAP_GEN}")

# jsoncpp: libjsoncpp_defaults.
aosp_library(jsoncpp
    SRCS "${JSONCPP}/src/lib_json/json_reader.cpp"
        "${JSONCPP}/src/lib_json/json_value.cpp"
        "${JSONCPP}/src/lib_json/json_writer.cpp"
    FLAGS -std=gnu++20 -DJSON_USE_EXCEPTION=0 -DJSONCPP_NO_LOCALE_SUPPORT
        -Wno-implicit-fallthrough
    INCLUDES "${JSONCPP}/src/lib_json" "${JSONCPP}/include")

set(LIBSYSUTILS_SRCS SocketListener.cpp FrameworkListener.cpp
    FrameworkCommand.cpp SocketClient.cpp ServiceManager.cpp)
list(TRANSFORM LIBSYSUTILS_SRCS PREPEND "${LIBSYSUTILS}/src/")
aosp_library(sysutils
    SRCS ${LIBSYSUTILS_SRCS}
    FLAGS -std=gnu++20
    INCLUDES "${LIBSYSUTILS}/include" ${SYSTEM_INCLUDES})

aosp_library(packagelistparser
    SRCS "${PKGLIST}/packagelistparser.cpp"
    FLAGS -std=gnu++20 -Wno-error
    INCLUDES "${PKGLIST}/include" ${SYSTEM_INCLUDES})

# libprocessgroup with libprocessgroup_util.
set(PROCESSGROUP_SRCS cgroup_map.cpp processgroup.cpp sched_policy.cpp
    task_profiles.cpp util/cgroup_controller.cpp util/cgroup_descriptor.cpp
    util/util.cpp)
list(TRANSFORM PROCESSGROUP_SRCS PREPEND "${PROCESSGROUP}/")
aosp_library(processgroup
    SRCS ${PROCESSGROUP_SRCS}
    FLAGS -std=gnu++23 -Wno-error
    INCLUDES "${PROCESSGROUP}" "${PROCESSGROUP}/util/include"
        "${JSONCPP}/include" ${SYSTEM_INCLUDES})

aosp_library(audit
    SRCS "${LOGD}/libaudit/libaudit.cpp"
    FLAGS -std=gnu++20 -Wno-error
    INCLUDES "${LOGD}/libaudit/include" "${LIBBASE}/include")

# liblogd and logd: logd_defaults.  LogdNativeService.cpp is the logd
# binder service, which LOGD_NO_BINDER leaves out.
set(LOGD_FLAGS -std=gnu++20 -Wextra -Wthread-safety -DAUDITD_LOG_TAG=1003
    -DTAG_DEF_LOG_TAG=1005 -DLIBLOG_LOG_TAG=1006 -DLOGD_NO_BINDER
    -Wno-error)
set(LOGD_INCLUDES "${LOGD}" "${LOGD}/libaudit/include" "${ZSTD}/lib"
    "${ZLIB_SRC}" "${LIBSYSUTILS}/include" "${PKGLIST}/include"
    "${LIBCAP}/libcap/include" ${SYSTEM_INCLUDES} "${LIBUTILS}/include")
set(LIBLOGD_SRCS CompressionEngine.cpp LogBufferElement.cpp
    LogReaderList.cpp LogReaderThread.cpp LogSize.cpp LogStatistics.cpp
    LogTags.cpp LogdLock.cpp PruneList.cpp SerializedFlushToState.cpp
    SerializedLogBuffer.cpp SerializedLogChunk.cpp SimpleLogBuffer.cpp)
list(TRANSFORM LIBLOGD_SRCS PREPEND "${LOGD}/")
aosp_library(logd_lib
    SRCS ${LIBLOGD_SRCS}
    FLAGS ${LOGD_FLAGS}
    INCLUDES ${LOGD_INCLUDES})

# A C++ program of the system partition, with libc++ static as in the test
# suites.
function(system_cxx_program name)
	cmake_parse_arguments(P "" "" "SRCS;LIBS;FLAGS;INCLUDES" ${ARGN})
	system_program(${name} SRCS ${P_SRCS}
	    LIBS -Wl,--start-group ${P_LIBS} ${LIBCXX_STATIC} -Wl,--end-group)
	target_include_directories(${name} SYSTEM BEFORE PRIVATE
	    "${CXX_INCLUDE}")
	target_include_directories(${name} PRIVATE ${P_INCLUDES})
	target_compile_options(${name} PRIVATE -D_FILE_OFFSET_BITS=64
	    -DNDEBUG ${AOSP_CXX_FLAGS} ${P_FLAGS})
endfunction()

set(LOGD_SRCS main.cpp CommandListener.cpp LogAudit.cpp LogKlog.cpp
    LogListener.cpp LogPermissions.cpp LogReader.cpp TrustyLog.cpp
    PkgIds.cpp)
list(TRANSFORM LOGD_SRCS PREPEND "${LOGD}/")
system_cxx_program(logd
    SRCS ${LOGD_SRCS}
    LIBS logd_lib audit sysutils packagelistparser processgroup jsoncpp
        cap utils cutils log base zstd z
    FLAGS ${LOGD_FLAGS}
    INCLUDES ${LOGD_INCLUDES})

# logwrapper: logwrapper_common.
system_cxx_program(logwrapper
    SRCS "${LOGWRAPPER}/logwrap.cpp" "${LOGWRAPPER}/logwrapper.cpp"
    LIBS cutils log base
    FLAGS -std=gnu++20 -Werror
    INCLUDES "${LOGWRAPPER}/include" ${SYSTEM_INCLUDES})

# protobuf for logcat: libprotobuf-cpp-lite and the abseil libraries for
# the device, and protoc for the build host.  The abseil libraries are the
# cc_library_static modules of its Android.bp, in one static library: a
# program links only the objects that it uses.  protoc comes from the
# host-protoc project, with the FreeBSD compiler.  This abseil deprecates the
# Mutex calls that protobuf makes, so that warning stays a warning.
set(ABSEIL "${AOSP_EXTERNAL}/abseil-cpp")
set(PROTOBUF "${AOSP_EXTERNAL}/protobuf")
execute_process(
    COMMAND "${AWK}" -f "${CMAKE_CURRENT_SOURCE_DIR}/absl-srcs.awk"
        "${ABSEIL}/Android.bp"
    OUTPUT_VARIABLE ABSL_SRCS RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
	message(FATAL_ERROR "absl-srcs.awk failed on ${ABSEIL}/Android.bp")
endif()
string(REGEX REPLACE "\n+" ";" ABSL_SRCS "${ABSL_SRCS}")
list(FILTER ABSL_SRCS INCLUDE REGEX "\\.cc$")
list(REMOVE_DUPLICATES ABSL_SRCS)
list(TRANSFORM ABSL_SRCS PREPEND "${ABSEIL}/")
aosp_library(absl
    SRCS ${ABSL_SRCS}
    FLAGS -std=gnu++20 -Wno-error
    INCLUDES "${ABSEIL}" "${LIBLOG}/include")

set(PROTOBUF_LITE_SRCS any_lite.cc arena.cc arena_align.cc arenastring.cc
    arenaz_sampler.cc extension_set.cc generated_enum_util.cc
    generated_message_tctable_lite.cc generated_message_util.cc
    implicit_weak_message.cc inlined_string_field.cc io/coded_stream.cc
    io/io_win32.cc io/zero_copy_sink.cc io/zero_copy_stream.cc
    io/zero_copy_stream_impl.cc io/zero_copy_stream_impl_lite.cc map.cc
    message_lite.cc micro_string.cc parse_context.cc port.cc raw_ptr.cc
    repeated_field.cc repeated_ptr_field.cc stubs/common.cc
    wire_format_lite.cc)
list(TRANSFORM PROTOBUF_LITE_SRCS PREPEND "${PROTOBUF}/src/google/protobuf/")
set(PROTOBUF_INCLUDES "${PROTOBUF}/src" "${PROTOBUF}/third_party/utf8_range"
    "${ABSEIL}")
aosp_library(protobuf_lite
    SRCS ${PROTOBUF_LITE_SRCS} "${PROTOBUF}/third_party/utf8_range/naive.c"
        "${PROTOBUF}/third_party/utf8_range/utf8_range.c"
    FLAGS $<$<COMPILE_LANGUAGE:CXX>:-std=gnu++20>
        -Wno-error=user-defined-warnings -Wno-missing-field-initializers
        -Wno-unused-function -Wno-unused-parameter
        -Wno-error=deprecated-declarations
    INCLUDES ${PROTOBUF_INCLUDES} "${LIBLOG}/include")

set(HOST_CXX c++ CACHE STRING "FreeBSD C++ compiler for the host programs")
include(ExternalProject)
ExternalProject_Add(host_protoc
    SOURCE_DIR "${PROJECT_ROOT}/aosp/cmake/host-protoc"
    BINARY_DIR "${GEN}/host-protoc"
    CMAKE_ARGS -DCMAKE_C_COMPILER=${HOST_CC} -DCMAKE_CXX_COMPILER=${HOST_CXX}
        -DCMAKE_BUILD_TYPE=Release -DABSEIL_SRC=${ABSEIL}
        -DPROTOBUF_SRC=${PROTOBUF}
    BUILD_COMMAND "${CMAKE_COMMAND}" --build <BINARY_DIR> --target protoc
    INSTALL_COMMAND ""
    BUILD_BYPRODUCTS "${GEN}/host-protoc/protobuf/protoc")
set(HOST_PROTOC "${GEN}/host-protoc/protobuf/protoc")

# logcat: logcat.proto is a lite proto, compiled as Soong compiles it.
set(LOGCAT "${AOSP_SYSTEM}/logging/logcat")
add_custom_command(
    OUTPUT "${GEN}/logcat_proto/logcat.pb.cc"
        "${GEN}/logcat_proto/logcat.pb.h"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${GEN}/logcat_proto"
    COMMAND "${HOST_PROTOC}" "--cpp_out=${GEN}/logcat_proto" -I "${LOGCAT}"
        "${LOGCAT}/logcat.proto"
    DEPENDS host_protoc "${LOGCAT}/logcat.proto"
    VERBATIM)
system_cxx_program(logcat
    SRCS "${LOGCAT}/logcat.cpp" "${LOGCAT}/process_names.cpp"
        "${GEN}/logcat_proto/logcat.pb.cc"
    LIBS processgroup jsoncpp utils cutils log base protobuf_lite absl
    FLAGS -std=gnu++20 -DANDROID_BASE_UNIQUE_FD_DISABLE_IMPLICIT_CONVERSION=1
        -Wno-error
    INCLUDES "${GEN}/logcat_proto" ${PROTOBUF_INCLUDES} ${SYSTEM_INCLUDES})

# svcstart starts a service in the jail as init would.  It is static, as
# propd is, because it runs before the Android root is complete.
add_executable(svcstart "${PROJECT_ROOT}/aosp/jail/svcstart/svcstart.cpp")
add_dependencies(svcstart crt)
target_include_directories(svcstart SYSTEM BEFORE PRIVATE "${CXX_INCLUDE}")
target_include_directories(svcstart PRIVATE
    "${AOSP_SYSTEM}/core/libcutils/include")
target_compile_options(svcstart PRIVATE -std=gnu++20 -Wall -Wextra -Werror
    ${AOSP_CXX_FLAGS})
target_link_options(svcstart PRIVATE -static -nostdlib -fuse-ld=lld
    -Wl,--gc-sections "${GEN}/crtbegin_static.o")
target_link_libraries(svcstart PRIVATE ${LIBCXX_STATIC} c_static
    "${GEN}/crtend.o")
set_target_properties(svcstart PROPERTIES
    LINK_DEPENDS "${GEN}/crtbegin_static.o")
if(BUILTINS_LIB)
	target_link_libraries(svcstart PRIVATE "${BUILTINS_LIB}")
endif()

# /system/etc: the event log tags of the modules here, merged as Soong
# merges them (one line for each tag, sorted by number); cgroups.json; and
# task_profiles.json.
set(LOGTAGS "${LOGD}/event.logtags" "${LIBLOG}/event.logtags"
    "${AOSP_SYSTEM}/logging/logcat/event.logtags"
    "${LIBSYSUTILS}/EventLogTags.logtags")
add_custom_command(OUTPUT "${GEN}/event-log-tags"
    COMMAND sh -c "cat \"$@\" | awk '!/^#/ && NF' | sort -n -u -k1,1 \
        > \"${GEN}/event-log-tags\"" sh ${LOGTAGS}
    DEPENDS ${LOGTAGS}
    VERBATIM)
# Each SetTimerSlack action is a "{" line, its "Name" line and the lines up
# to the "}" in the column of the "{".
add_custom_command(OUTPUT "${GEN}/task_profiles.json"
    COMMAND "${AWK}" "
        skip { if (match($0, /[^ ]/) == col && $0 ~ /^ *}/) skip = 0; next }
        held != \"\" {
            if ($0 ~ /\"Name\": \"SetTimerSlack\"/) {
                col = match(held, /[^ ]/); skip = 1; held = \"\"; next
            }
            print held; held = \"\"
        }
        /^ *{ *$/ { held = $0; next }
        { print }" "${PROCESSGROUP}/profiles/task_profiles.json"
        > "${GEN}/task_profiles.json"
    DEPENDS "${PROCESSGROUP}/profiles/task_profiles.json"
    VERBATIM)
add_custom_command(OUTPUT "${GEN}/cgroups.json"
    COMMAND sh -c "echo '{ \"Cgroups\": [] }' > \"${GEN}/cgroups.json\""
    VERBATIM)

add_custom_target(android_root_logd ALL
    COMMAND "${CMAKE_COMMAND}" -E copy $<TARGET_FILE:logd>
        $<TARGET_FILE:logwrapper> $<TARGET_FILE:logcat>
        "${ROOT}/system/bin"
    COMMAND "${CMAKE_COMMAND}" -E copy "${GEN}/event-log-tags"
        "${GEN}/task_profiles.json" "${GEN}/cgroups.json"
        "${ROOT}/system/etc"
    DEPENDS logd logwrapper logcat "${GEN}/event-log-tags"
        "${GEN}/task_profiles.json" "${GEN}/cgroups.json"
    VERBATIM)
add_dependencies(android_root_logd android_root_platform)

# Two logwrapper processes write through logd, and "logcat -d" shows both.
add_test(NAME logcat_two_processes
    COMMAND sh "${CMAKE_CURRENT_SOURCE_DIR}/logcat-two-processes.sh"
        "${GEN}/bionic-tests-jail.conf")
