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
# Soong's flags for device code, as build/soong/cc gives them to a module
# of the product aosp_cf_arm64_only_phone in the release cp2a.  The group
# names follow cc/config/global.go, and the order of the groups follows
# cc/builder.go: global, then the module's own flags, then the groups that
# a module cannot override.  docs/specs/soong-flags.md has the source line
# of each flag.
#
#   soong_cc(<target> [EXTERNAL] [TEST] [GTEST] [PROTO] [CC_OBJECT]
#       [STATIC] [RTTI] [NO_WERROR] [LTO_NEVER] [LTO_THIN]
#       [NO_PACK_RELOCATIONS] [ALLOW_UNDEFINED] [AFDO]
#       [MODULE <Android.bp name>] [C_STD <std>] [CPP_STD <std>])
#
# gives a target its global groups.  Call it right after add_library() or
# add_executable(), before the target's own options; the target's own
# options are the cflags, conlyflags, cppflags and asflags of its
# Android.bp module, each for its own languages.  A -std= of conlyflags or
# cppflags, and the c_std and cpp_std properties, go in C_STD and
# CPP_STD.  soong_finalize(), once after the last target, adds the rest.
# CMake drops repeated options, which would change the order that Soong
# relies on, so each group goes in as one SHELL: option.
#
# A static library takes the LTO state and the AFDO profile of the module
# that links it (cc/lto.go and cc/afdo.go give a static dependency a
# variant of its own).  soong_finalize() makes such a variant as a copy of
# the library and points the user at the copy.  A copy loses the SYSTEM
# mark of a private include directory, so add those with
# soong_system_includes().

# Global common flags, for C, C++ and assembly.  -nostdlibinc: a device
# module has no host headers; then arm64Cflags with the page size macro of
# a product that keeps it, commonGlobalCflags with the two flags that
# CommonGlobalCflags adds, and deviceGlobalCflags.
set(SOONG_GLOBAL_CFLAGS -nostdlibinc
    -Werror=implicit-function-declaration -fstack-clash-protection
    -D__BIONIC_DEPRECATED_PAGE_SIZE_MACRO
    -O2 -Wall -Wextra -Wpointer-arith -Wunguarded-availability
    -Werror=bool-operation -Werror=date-time -Werror=format-security
    -Werror=int-conversion -Werror=multichar -Werror=pragma-pack
    -Werror=pragma-pack-suspicious-include -Werror=sizeof-array-div
    -Werror=sizeof-pointer-memaccess -Werror=string-plus-int
    -Werror=unreachable-code-loop-increment -Wno-error=deprecated-declarations
    -Wno-c23-extensions -Wno-c99-designator -Wno-gnu-folding-constant
    -Wno-inconsistent-missing-override -Wno-error=reorder-init-list
    -Wno-reorder-init-list -Wno-sign-compare -Wno-unused
    -DANDROID -DNDEBUG -UDEBUG -D__compiler_offsetof=__builtin_offsetof
    -D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__
    -faddrsig -fdebug-default-version=5 -fcolor-diagnostics -ffp-contract=off
    -fno-exceptions -fno-strict-aliasing -fmessage-length=0
    -gsimple-template-names -gz=zstd -no-canonical-prefixes
    -ftrivial-auto-var-init=zero -g
    -ffunction-sections -fdata-sections -fno-short-enums -funwind-tables
    -Wa,--noexecstack -D_FORTIFY_SOURCE=3 -fstack-protector-strong
    -Werror=non-virtual-dtor -Werror=address -Werror=sequence-point)
set(SOONG_TESTS_CFLAGS -Wno-error=unused-but-set-variable)
set(SOONG_EXTERNAL_CFLAGS -Wno-enum-compare -Wno-enum-compare-switch
    -Wno-null-pointer-arithmetic -Wno-null-pointer-subtraction
    -Wno-string-concatenation -Wno-deprecated-non-prototype -Wno-unused
    -Wno-unused-but-set-variable -Wno-deprecated
    -Wno-tautological-constant-compare)
# The armv8-a variant and the cortex-a53 CPU of the board.
set(SOONG_TOOLCHAIN_CFLAGS -march=armv8-a -mcpu=cortex-a53)
set(SOONG_GLOBAL_CPPFLAGS -Wimplicit-fallthrough
    -D_LIBCPP_ENABLE_THREAD_SAFETY_ANNOTATIONS -Wno-gnu-include-next
    -fvisibility-inlines-hidden)
set(SOONG_GLOBAL_ASFLAGS -D__ASSEMBLY__ -fdebug-default-version=4)

# noOverrideGlobalCflags, and the tests and external groups after it.
# -fcommon: RELEASE_SOONG_FNO_COMMON_FOR_3P_CODE is false in cp2a.
set(SOONG_NO_OVERRIDE_CFLAGS -Werror=address-of-temporary -Werror=dangling
    -Werror=format-insufficient-args -Werror=fortify-source
    -Werror=incompatible-function-pointer-types -Werror=int-in-bool-context
    -Werror=int-to-pointer-cast -Werror=null-dereference -Werror=return-type
    -Werror=xor-used-as-pow -Wno-missing-field-initializers -Wno-packed-non-pod
    -Wno-error=tautological-constant-compare -Wno-implicit-int-float-conversion
    -Wno-tautological-overlap-compare -Wno-deprecated-copy
    -Wno-zero-as-null-pointer-constant -Wno-deprecated-anon-enum-enum-conversion
    -Wno-deprecated-enum-enum-conversion -Wno-error=pessimizing-move
    -Wno-non-c-typedef-for-linkage -Wno-align-mismatch
    -Wno-error=unused-but-set-parameter -Wno-error=deprecated
    -Wno-error=invalid-offsetof -Wno-nontrivial-memcall
    -Wno-invalid-specialization -Wno-unterminated-string-initialization
    -Wno-implicit-int-conversion-on-negation
    -Wno-default-const-init-field-unsafe -Wno-default-const-init-var-unsafe
    -Wno-preferred-type-bitfield-enum-conversion -Wno-implicit-enum-enum-cast
    -Wno-character-conversion -Wno-error=uninitialized-const-pointer
    -Wno-incompatible-pointer-types -Wno-c2y-extensions -Wno-vla-cxx-extension
    -Wno-cast-function-type-mismatch)
set(SOONG_NO_OVERRIDE_TESTS_CFLAGS -Wno-unused-variable)
set(SOONG_NO_OVERRIDE_EXTERNAL_CFLAGS -Wno-format-insufficient-args
    -Wno-misleading-indentation -Wno-unused -Wno-unused-parameter
    -Wno-unused-but-set-parameter -Wno-unused-variable
    -Wno-unqualified-std-cast-call -Wno-array-parameter
    -Wno-gnu-offsetof-extensions -Wno-pessimizing-move -Wno-pointer-to-int-cast
    -fcommon)

# deviceGlobalLdflags with commonGlobalLdflags, then the arm64 flags of the
# toolchain and of the cortex-a53 variant.
set(SOONG_GLOBAL_LDFLAGS -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now
    -Wl,--build-id=md5 -Wl,--fatal-warnings -Wl,--no-undefined-version
    -Wl,--exclude-libs,libgcc.a -Wl,--exclude-libs,libgcc_stripped.a
    -Wl,--exclude-libs,libunwind_llvm.a -Wl,--exclude-libs,libunwind.a
    -Wl,--compress-debug-sections=zstd -fuse-ld=lld -Wl,--icf=safe
    -Wl,--no-demangle)
set(SOONG_ARM64_LDFLAGS -Wl,-z,separate-code -Wl,-z,separate-loadable-segments
    -Wl,-z,max-page-size=16384)
set(SOONG_TOOLCHAIN_LDFLAGS ${SOONG_ARM64_LDFLAGS}
    -Wl,--fix-cortex-a53-843419)

# strip.go: Soong installs each device program and shared library
# stripped.  SOONG_STRIP is the command that makes the installed copy
# (soong-strip.sh), with the LLVM tools of the compiler, as Soong takes
# them from its clang.
foreach(t strip objcopy nm)
	string(TOUPPER ${t} v)
	execute_process(COMMAND "${CMAKE_C_COMPILER}" -print-prog-name=llvm-${t}
	    OUTPUT_VARIABLE p OUTPUT_STRIP_TRAILING_WHITESPACE)
	if(NOT IS_ABSOLUTE "${p}" OR NOT EXISTS "${p}")
		message(FATAL_ERROR "${CMAKE_C_COMPILER} has no llvm-${t}")
	endif()
	set(SOONG_LLVM_${v} "${p}")
endforeach()
find_program(SOONG_XZ xz REQUIRED)
set(SOONG_STRIP "${CMAKE_COMMAND}" -E env "LLVM_STRIP=${SOONG_LLVM_STRIP}"
    "LLVM_OBJCOPY=${SOONG_LLVM_OBJCOPY}" "LLVM_NM=${SOONG_LLVM_NM}"
    "XZ=${SOONG_XZ}" sh "${CMAKE_CURRENT_LIST_DIR}/soong-strip.sh")

# ThinLTO.  lto.go also adds -Wl,-mllvm,-regalloc-enable-advisor=release
# on arm64; the LLVM of the ports has no release model for it (register
# row T15-G1).
set(SOONG_LTO_CFLAGS -flto=thin -fsplit-lto-unit)

# The AFDO profiles of RELEASE_BUILD_AFDO_PROFILE_VERSION in cp2a, by
# module name (toolchain/pgo-profiles/sampling/Android.bp).
set(PGO_PROFILES "/home/dev/aosp/toolchain/pgo-profiles" CACHE PATH
    "toolchain/pgo-profiles checkout at the pinned build")
set(SOONG_AFDO_DIR "${PGO_PROFILES}/sampling/15119254-next")
set(SOONG_AFDO_libc bionic_libc_arm64.afdo)
set(SOONG_AFDO_libcrypto libcrypto.afdo)
set(SOONG_AFDO_liblog liblog.afdo)
set(SOONG_AFDO_libutils libutils.afdo)
set(SOONG_AFDO_libz libz_arm64.afdo)
set(SOONG_AFDO_linker linker_arm64.afdo)

# The properties that soong_finalize() saves before it changes them, and
# that a variant starts from.
set(SOONG_SAVED SOURCES INCLUDE_DIRECTORIES COMPILE_DEFINITIONS
    COMPILE_OPTIONS LINK_LIBRARIES INTERFACE_LINK_LIBRARIES
    INTERFACE_INCLUDE_DIRECTORIES INTERFACE_SYSTEM_INCLUDE_DIRECTORIES
    INTERFACE_COMPILE_DEFINITIONS INTERFACE_COMPILE_OPTIONS)

# _soong_shell(<var> <flags>...): one SHELL: option with the flags.
function(_soong_shell var)
	list(JOIN ARGN " " s)
	set(${var} "SHELL:${s}" PARENT_SCOPE)
endfunction()

function(soong_system_includes target)
	target_include_directories(${target} SYSTEM BEFORE PRIVATE ${ARGN})
	set_property(TARGET ${target} APPEND PROPERTY SOONG_SYSTEM_INCLUDES
	    ${ARGN})
endfunction()

function(soong_cc target)
	cmake_parse_arguments(S "EXTERNAL;TEST;GTEST;PROTO;CC_OBJECT;STATIC;RTTI;NO_WERROR;LTO_NEVER;LTO_THIN;NO_PACK_RELOCATIONS;ALLOW_UNDEFINED;AFDO"
	    "MODULE;C_STD;CPP_STD" "" ${ARGN})
	if(NOT S_C_STD)
		set(S_C_STD gnu23)
	endif()
	if(NOT S_CPP_STD)
		set(S_CPP_STD gnu++20)
	endif()
	get_target_property(type ${target} TYPE)
	set(common ${SOONG_GLOBAL_CFLAGS})
	if(S_TEST)
		list(APPEND common ${SOONG_TESTS_CFLAGS})
	endif()
	if(S_EXTERNAL)
		list(APPEND common ${SOONG_EXTERNAL_CFLAGS})
	endif()
	list(APPEND common ${SOONG_TOOLCHAIN_CFLAGS})
	_soong_shell(common ${common})
	_soong_shell(cpp ${SOONG_GLOBAL_CPPFLAGS})
	_soong_shell(as ${SOONG_GLOBAL_ASFLAGS})
	set(opts "${common}")
	# compiler.go: -DANDROID_STRICT outside external/, then the start of
	# the module's own flags: -Werror.
	if(NOT S_EXTERNAL)
		list(APPEND opts "$<$<COMPILE_LANGUAGE:C,CXX>:-DANDROID_STRICT>")
	endif()
	list(APPEND opts "$<$<COMPILE_LANGUAGE:CXX>:${cpp}>"
	    "$<$<COMPILE_LANGUAGE:ASM>:${as}>")
	if(NOT S_NO_WERROR)
		list(APPEND opts "$<$<COMPILE_LANGUAGE:C,CXX>:SHELL:-Werror>")
	endif()
	target_compile_options(${target} PRIVATE ${opts})
	if(type STREQUAL "SHARED_LIBRARY" OR type STREQUAL "EXECUTABLE")
		set(ld ${SOONG_GLOBAL_LDFLAGS})
		if(NOT S_ALLOW_UNDEFINED)
			list(APPEND ld -Wl,--no-undefined)
		endif()
		list(APPEND ld ${SOONG_ARM64_LDFLAGS} ${SOONG_TOOLCHAIN_LDFLAGS})
		if(S_NO_PACK_RELOCATIONS)
			list(APPEND ld -Wl,--pack-dyn-relocs=none)
		else()
			list(APPEND ld -Wl,--pack-dyn-relocs=android+relr)
		endif()
		if(type STREQUAL "SHARED_LIBRARY")
			list(APPEND ld -nostdlib -Wl,--gc-sections)
			# Soong defines no <target>_EXPORTS macro.
			set_target_properties(${target} PROPERTIES DEFINE_SYMBOL "")
		elseif(S_STATIC)
			list(APPEND ld -static -nostdlib -Bstatic -Wl,--gc-sections)
		else()
			list(APPEND ld -pie -nostdlib -Bdynamic -Wl,--gc-sections
			    -Wl,-z,nocopyreloc
			    -Wl,--dynamic-linker=/system/bin/linker64)
		endif()
		_soong_shell(ld ${ld})
		target_link_options(${target} PRIVATE "${ld}")
		# test.go: a test program finds its data libraries next to
		# it.
		if(type STREQUAL "EXECUTABLE" AND S_TEST)
			target_link_options(${target} PRIVATE "-Wl,-rpath,\$ORIGIN")
		endif()
	endif()
	# lto.go: on for a module that is not a test, unless it has
	# lto: { never: true }; lto: { thin: true } sets it on.  A cc_object
	# has no LTO and no AFDO (object.go).
	if(S_LTO_NEVER OR S_CC_OBJECT OR (S_TEST AND NOT S_LTO_THIN))
		set(lto OFF)
	else()
		set(lto ON)
	endif()
	if(S_CC_OBJECT)
		set(S_LTO_NEVER ON)
		set(S_AFDO OFF)
	endif()
	set_target_properties(${target} PROPERTIES SOONG_LTO ${lto}
	    SOONG_LTO_NEVER "${S_LTO_NEVER}" SOONG_AFDO_SELF "${S_AFDO}"
	    SOONG_MODULE "${S_MODULE}" SOONG_RTTI "${S_RTTI}"
	    SOONG_TEST "${S_TEST}" SOONG_EXTERNAL "${S_EXTERNAL}"
	    SOONG_STATIC "${S_STATIC}" SOONG_GTEST "${S_GTEST}"
	    SOONG_PROTO "${S_PROTO}" SOONG_CC_OBJECT "${S_CC_OBJECT}"
	    SOONG_C_STD ${S_C_STD} SOONG_CPP_STD ${S_CPP_STD}
	    SOONG_VARIATION "")
	set_property(GLOBAL APPEND PROPERTY SOONG_TARGETS ${target})
endfunction()

# _soong_linked(<target> <var>): true for a target that the linker makes,
# a shared library or a program.
function(_soong_linked target var)
	get_target_property(type ${target} TYPE)
	if(type STREQUAL "SHARED_LIBRARY" OR type STREQUAL "EXECUTABLE")
		set(${var} ON PARENT_SCOPE)
	else()
		set(${var} OFF PARENT_SCOPE)
	endif()
endfunction()

# _soong_local(<target> <lto> <variation>): the flags after the module's
# own flags, in Soong's order.  The local cflags end with the defines of
# the module type (compiler.go, proto.go, test.go, object.go) and the LTO
# flags; the conlyflags and the cppflags, which come after the cflags,
# start with the language standard, and the cppflags end with -fno-rtti.
# Soong puts the AFDO flags before the module's flags, but no module flag
# changes them, so their place here has the same effect.  The LTO flags
# also go to assembly; the no-override groups come at the end.
function(_soong_local target lto variation)
	get_target_property(rtti ${target} SOONG_RTTI)
	get_target_property(test ${target} SOONG_TEST)
	get_target_property(external ${target} SOONG_EXTERNAL)
	get_target_property(self ${target} SOONG_AFDO_SELF)
	get_target_property(module ${target} SOONG_MODULE)
	get_target_property(gtest ${target} SOONG_GTEST)
	get_target_property(proto ${target} SOONG_PROTO)
	get_target_property(object ${target} SOONG_CC_OBJECT)
	get_target_property(cstd ${target} SOONG_C_STD)
	get_target_property(cppstd ${target} SOONG_CPP_STD)
	_soong_linked(${target} linked)
	set(type_flags)
	if(proto)
		list(APPEND type_flags -DGOOGLE_PROTOBUF_NO_RTTI)
	endif()
	if(object)
		# Clang's address-significance tables do not survive ld -r.
		list(APPEND type_flags -fno-addrsig)
	endif()
	if(gtest)
		list(APPEND type_flags -DGTEST_HAS_STD_STRING -DGTEST_OS_LINUX_ANDROID)
	endif()
	# afdo.go: a module with afdo: true, or a static dependency of one,
	# gets the discriminator flags.  The profile is the one of the
	# variation, or the module's own if it is not a static library.
	set(profile "")
	set(afdo OFF)
	if(NOT variation STREQUAL "")
		set(afdo ON)
		set(profile "${variation}")
	elseif(self)
		set(afdo ON)
		if(linked)
			set(profile "${module}")
		endif()
	endif()
	set(c)
	set(ld)
	set(limit 5)
	if(afdo)
		set(c -mllvm -improved-fs-discriminator=true -mllvm
		    -enable-fs-discriminator=true -funique-internal-linkage-names
		    -fdebug-info-for-profiling)
		set(ld -Wl,-mllvm,-improved-fs-discriminator=true
		    -Wl,-mllvm,-enable-fs-discriminator=true)
		if(NOT profile STREQUAL "" AND DEFINED SOONG_AFDO_${profile})
			set(p "${SOONG_AFDO_DIR}/${SOONG_AFDO_${profile}}")
			if(NOT EXISTS "${p}")
				message(FATAL_ERROR "${p} is missing; run aosp/fetch.sh "
				    "--project toolchain/pgo-profiles")
			endif()
			set(use -fprofile-sample-use=${p} -fsample-profile-use-profi
			    -fprofile-sample-accurate)
			list(PREPEND c -mllvm --salvage-stale-profile-max-callsites=2000
			    -mllvm --salvage-stale-profile=true ${use})
			list(PREPEND ld ${use} -Wl,-mllvm,-no-warn-sample-unused=true)
			set(limit 40)
		endif()
	endif()
	if(rtti)
		set(r -frtti)
	else()
		set(r -fno-rtti)
	endif()
	set(opts)
	if(type_flags)
		_soong_shell(t ${type_flags})
		list(APPEND opts "$<$<COMPILE_LANGUAGE:C,CXX>:${t}>")
	endif()
	if(c)
		_soong_shell(c ${c})
		list(APPEND opts "$<$<COMPILE_LANGUAGE:C,CXX>:${c}>")
	endif()
	if(lto)
		_soong_shell(l ${SOONG_LTO_CFLAGS})
		list(APPEND opts "${l}")
	endif()
	list(APPEND opts "$<$<COMPILE_LANGUAGE:C>:SHELL:-std=${cstd}>"
	    "$<$<COMPILE_LANGUAGE:CXX>:SHELL:-std=${cppstd} ${r}>")
	set(no ${SOONG_NO_OVERRIDE_CFLAGS})
	if(test)
		list(APPEND no ${SOONG_NO_OVERRIDE_TESTS_CFLAGS})
	endif()
	if(external)
		list(APPEND no ${SOONG_NO_OVERRIDE_EXTERNAL_CFLAGS})
	endif()
	_soong_shell(no ${no})
	list(APPEND opts "$<$<COMPILE_LANGUAGE:C,CXX>:${no}>")
	target_compile_options(${target} PRIVATE ${opts})
	if(linked)
		if(lto)
			list(APPEND ld ${SOONG_LTO_CFLAGS}
			    -Wl,-plugin-opt,-import-instr-limit=${limit})
		endif()
		if(ld)
			_soong_shell(ld ${ld})
			target_link_options(${target} PRIVATE "${ld}")
		endif()
	endif()
endfunction()

# _soong_deps(<target> <var>): the recorded libraries that a target links
# or takes the objects of, from the saved properties.
function(_soong_deps target var)
	get_property(all GLOBAL PROPERTY SOONG_TARGETS)
	get_target_property(libs ${target} SOONG_SAVED_LINK_LIBRARIES)
	get_target_property(ilibs ${target} SOONG_SAVED_INTERFACE_LINK_LIBRARIES)
	get_target_property(srcs ${target} SOONG_SAVED_SOURCES)
	set(deps)
	foreach(l IN LISTS libs ilibs)
		string(REGEX REPLACE "^\\$<LINK_ONLY:(.*)>$" "\\1" l "${l}")
		if(l IN_LIST all)
			list(APPEND deps ${l})
		endif()
	endforeach()
	foreach(s IN LISTS srcs)
		if(s MATCHES "^\\$<TARGET_OBJECTS:([^>]+)>$" AND
		    CMAKE_MATCH_1 IN_LIST all)
			list(APPEND deps ${CMAKE_MATCH_1})
		endif()
	endforeach()
	list(REMOVE_DUPLICATES deps)
	set(${var} ${deps} PARENT_SCOPE)
endfunction()

# _soong_rename(<target> <from> <to>): point the links and the object
# sources of a target at another variant.
function(_soong_rename target from to)
	foreach(p LINK_LIBRARIES INTERFACE_LINK_LIBRARIES SOURCES)
		get_target_property(v ${target} ${p})
		if(NOT v)
			continue()
		endif()
		set(n)
		foreach(i IN LISTS v)
			if(i STREQUAL "${from}")
				set(i "${to}")
			elseif(i STREQUAL "$<LINK_ONLY:${from}>")
				set(i "$<LINK_ONLY:${to}>")
			elseif(i STREQUAL "$<TARGET_OBJECTS:${from}>")
				set(i "$<TARGET_OBJECTS:${to}>")
			endif()
			list(APPEND n "${i}")
		endforeach()
		set_property(TARGET ${target} PROPERTY ${p} "${n}")
	endforeach()
endfunction()

# _soong_copy(<from> <to>): a variant of a library, from its saved
# properties.
function(_soong_copy from to)
	get_target_property(type ${from} TYPE)
	if(type STREQUAL "OBJECT_LIBRARY")
		add_library(${to} OBJECT)
	else()
		add_library(${to} STATIC)
	endif()
	set_target_properties(${to} PROPERTIES EXCLUDE_FROM_ALL ON)
	foreach(p IN LISTS SOONG_SAVED)
		get_target_property(v ${from} SOONG_SAVED_${p})
		if(v)
			set_property(TARGET ${to} PROPERTY ${p} "${v}")
			set_property(TARGET ${to} PROPERTY SOONG_SAVED_${p} "${v}")
		endif()
	endforeach()
	get_target_property(sys ${from} SOONG_SYSTEM_INCLUDES)
	if(sys)
		target_include_directories(${to} SYSTEM BEFORE PRIVATE ${sys})
	endif()
	foreach(p SOONG_LTO_NEVER SOONG_AFDO_SELF SOONG_MODULE SOONG_RTTI
	    SOONG_TEST SOONG_EXTERNAL SOONG_STATIC SOONG_GTEST SOONG_PROTO
	    SOONG_CC_OBJECT SOONG_C_STD SOONG_CPP_STD POSITION_INDEPENDENT_CODE)
		get_target_property(v ${from} ${p})
		set_property(TARGET ${to} PROPERTY ${p} "${v}")
	endforeach()
	get_target_property(deps ${from} MANUALLY_ADDED_DEPENDENCIES)
	if(deps)
		add_dependencies(${to} ${deps})
	endif()
endfunction()

# _soong_resolve(<target> <lto> <variation>): give each library of a
# target the variant that the target needs (lto.go and afdo.go), make the
# variants that do not exist yet, and finish each one once.
function(_soong_resolve target lto variation)
	_soong_deps(${target} deps)
	foreach(d IN LISTS deps)
		# A shared library is a module of its own: it has no variants.
		_soong_linked(${d} dlinked)
		if(dlinked)
			continue()
		endif()
		get_target_property(never ${d} SOONG_LTO_NEVER)
		get_target_property(object ${d} SOONG_CC_OBJECT)
		get_target_property(dlto ${d} SOONG_LTO)
		if(never)
			set(want OFF)
		else()
			set(want ${lto})
		endif()
		set(dvar "${variation}")
		if(object)
			set(dvar "")
		endif()
		if(want STREQUAL dlto AND dvar STREQUAL "")
			set(v ${d})
		else()
			set(v "${d}__lto${want}_afdo${dvar}")
			if(NOT TARGET ${v})
				_soong_copy(${d} ${v})
				set_target_properties(${v} PROPERTIES SOONG_LTO ${want}
				    SOONG_VARIATION "${dvar}")
			endif()
			_soong_rename(${target} ${d} ${v})
		endif()
		get_target_property(done ${v} SOONG_DONE)
		if(NOT done)
			set_target_properties(${v} PROPERTIES SOONG_DONE ON)
			_soong_resolve(${v} ${want} "${dvar}")
			_soong_local(${v} ${want} "${dvar}")
		endif()
	endforeach()
endfunction()

# soong_finalize(): once, after the last target.  The linked targets come
# first, because they choose the variants of their libraries.
function(soong_finalize)
	get_property(all GLOBAL PROPERTY SOONG_TARGETS)
	foreach(t IN LISTS all)
		foreach(p IN LISTS SOONG_SAVED)
			get_target_property(v ${t} ${p})
			if(v)
				set_property(TARGET ${t} PROPERTY SOONG_SAVED_${p} "${v}")
			endif()
		endforeach()
	endforeach()
	foreach(t IN LISTS all)
		_soong_linked(${t} linked)
		if(NOT linked)
			continue()
		endif()
		get_target_property(lto ${t} SOONG_LTO)
		get_target_property(self ${t} SOONG_AFDO_SELF)
		get_target_property(static ${t} SOONG_STATIC)
		get_target_property(module ${t} SOONG_MODULE)
		# afdo.go: a module with afdo: true gives its name to its static
		# libraries, unless it is a static program.
		set(variation "")
		if(self AND NOT static)
			set(variation "${module}")
		endif()
		set_target_properties(${t} PROPERTIES SOONG_DONE ON)
		_soong_resolve(${t} ${lto} "${variation}")
		_soong_local(${t} ${lto} "")
	endforeach()
	# A library that no linked target uses keeps its own state.
	foreach(t IN LISTS all)
		get_target_property(done ${t} SOONG_DONE)
		if(NOT done)
			get_target_property(lto ${t} SOONG_LTO)
			set_target_properties(${t} PROPERTIES SOONG_DONE ON)
			_soong_resolve(${t} ${lto} "")
			_soong_local(${t} ${lto} "")
		endif()
	endforeach()
endfunction()
