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
# toybox, as Android builds the toybox module of external/toybox/Android.bp
# for /system: toybox-defaults and toybox-shared-defaults with the android
# target.  Soong applies the linux target to Android too, so linux_srcs are
# part of it.  The configuration is the generated one of android/device.
# It goes to /system/bin with one link for each name of toybox_symlinks.
# The FreeBSD backends are the patches of aosp/patches/toybox.

set(TOYBOX "${AOSP_EXTERNAL}/toybox" CACHE PATH
    "AOSP toybox checkout at the pinned build, with aosp/patches/toybox")
if(NOT EXISTS "${TOYBOX}/android/device/generated/config.h")
	message(FATAL_ERROR "toybox is missing; run aosp/fetch.sh "
	    "--project platform/external/toybox:android,lib,toys")
endif()

# all_srcs, linux_srcs and device_srcs of Android.bp.
set(TOYBOX_ALL_SRCS lib/args lib/commas lib/dirtree lib/elf lib/env lib/hash
    lib/lib lib/llist lib/net lib/portability lib/tty lib/utf8 lib/xwrap main
    toys/lsb/gzip toys/lsb/hostname toys/lsb/md5sum toys/lsb/mktemp
    toys/lsb/seq toys/net/microcom toys/other/dos2unix toys/other/getopt
    toys/other/readlink toys/other/setsid toys/other/stat toys/other/timeout
    toys/other/truncate toys/other/which toys/other/xxd toys/other/yes
    toys/pending/diff toys/pending/expr toys/pending/tr toys/posix/basename
    toys/posix/cat toys/posix/chmod toys/posix/cmp toys/posix/comm
    toys/posix/cp toys/posix/cpio toys/posix/cut toys/posix/date toys/posix/dd
    toys/posix/dirname toys/posix/du toys/posix/echo toys/posix/env
    toys/posix/file toys/posix/find toys/posix/getconf toys/posix/grep
    toys/posix/head toys/posix/id toys/posix/ln toys/posix/ls toys/posix/mkdir
    toys/posix/nl toys/posix/od toys/posix/paste toys/posix/patch
    toys/posix/printf toys/posix/pwd toys/posix/rm toys/posix/rmdir
    toys/posix/sed toys/posix/sleep toys/posix/sort toys/posix/tail
    toys/posix/tar toys/posix/tee toys/posix/test toys/posix/touch
    toys/posix/true toys/posix/uname toys/posix/uniq toys/posix/wc
    toys/posix/xargs)
set(TOYBOX_LINUX_SRCS toys/lsb/mount toys/lsb/umount toys/posix/ps
    toys/other/flock toys/other/nsenter toys/other/taskset)
set(TOYBOX_DEVICE_SRCS toys/android/getenforce toys/android/load_policy
    toys/android/log toys/android/restorecon toys/android/runcon
    toys/android/sendevent toys/android/setenforce toys/lsb/dmesg
    toys/lsb/killall toys/lsb/mknod toys/lsb/pidof toys/lsb/sync
    toys/net/ifconfig toys/net/netcat toys/net/netstat toys/net/ping
    toys/net/rfkill toys/net/tunctl toys/other/acpi toys/other/base64
    toys/other/blkdiscard toys/other/blkid toys/other/blockdev toys/other/chcon
    toys/other/chroot toys/other/chrt toys/other/clear toys/other/devmem
    toys/other/fallocate toys/other/fmt toys/other/free toys/other/freeramdisk
    toys/other/fsfreeze toys/other/fsync toys/other/gpiod toys/other/help
    toys/other/hwclock toys/other/i2ctools toys/other/inotifyd
    toys/other/insmod toys/other/ionice toys/other/losetup toys/other/lsattr
    toys/other/lsmod toys/other/lsusb toys/other/makedevs toys/other/memeater
    toys/other/mkswap toys/other/modinfo toys/other/mountpoint
    toys/other/nbd_client toys/other/partprobe toys/other/pivot_root
    toys/other/pmap toys/other/printenv toys/other/pwdx toys/other/readelf
    toys/other/rev toys/other/rmmod toys/other/rtcwake toys/other/setfattr
    toys/other/swapoff toys/other/swapon toys/other/sysctl toys/other/tac
    toys/other/uclampset toys/other/uptime toys/other/usleep toys/other/uuidgen
    toys/other/vconfig toys/other/vmstat toys/other/watch toys/pending/brctl
    toys/pending/dhcp toys/pending/getfattr toys/pending/lsof
    toys/pending/modprobe toys/pending/more toys/pending/stty
    toys/pending/traceroute toys/pending/vi toys/posix/cal toys/posix/chgrp
    toys/posix/cksum toys/posix/df toys/posix/expand toys/posix/false
    toys/posix/iconv toys/posix/kill toys/posix/logger toys/posix/mkfifo
    toys/posix/nice toys/posix/nohup toys/posix/renice toys/posix/split
    toys/posix/strings toys/posix/time toys/posix/tty toys/posix/ulimit
    toys/posix/unlink toys/posix/uudecode toys/posix/uuencode)
set(TOYBOX_SRCS ${TOYBOX_ALL_SRCS} ${TOYBOX_LINUX_SRCS} ${TOYBOX_DEVICE_SRCS})
list(TRANSFORM TOYBOX_SRCS PREPEND "${TOYBOX}/")
list(TRANSFORM TOYBOX_SRCS APPEND ".c")

# The cflags of toybox-defaults, and -DANDROID and -DNDEBUG of Soong's global
# flags.  stl: "none", and the shared libraries of the android target.
system_program(toybox SRCS ${TOYBOX_SRCS}
    LIBS crypto_shared log_shared selinux_shared z_shared)
add_dependencies(toybox crypto_hashed)
target_include_directories(toybox PRIVATE "${TOYBOX}/android/device"
    "${TOYBOX}" "${BORINGSSL}/src/include" "${LIBLOG}/include"
    "${SELINUX}/include" "${ZLIB}")
target_compile_options(toybox PRIVATE -DANDROID -DNDEBUG -Os -Wall -Werror
    -Wno-char-subscripts -Wno-deprecated-declarations
    -Wno-invalid-source-encoding -Wno-missing-field-initializers
    -Wno-pointer-arith -Wno-pointer-sign -Wno-sign-compare
    -Wno-string-plus-int -Wno-unused-parameter -Wno-unused-variable
    -funsigned-char -ffunction-sections -fdata-sections
    -fno-asynchronous-unwind-tables "-DTOYBOX_VENDOR=\"-android\"")

# toybox_symlinks of Android.bp: relative links in /system/bin.  CMake does
# not split a list after a "[", so the "[" link is in the command.
set(TOYBOX_LINKS acpi base64 basename blkdiscard blockdev brctl cal cat
    chattr chcon chgrp chmod chown chroot chrt cksum clear comm cmp cp cpio cut
    date dd devmem df diff dirname dmesg dos2unix du echo egrep env expand expr
    fallocate false fgrep file find flock fmt free fsync getconf getenforce
    getfattr getopt gpiodetect gpiofind gpioget gpioinfo gpioset grep groups
    gunzip gzip head hostname hwclock i2cdetect i2cdump i2cget i2cset
    i2ctransfer iconv id ifconfig inotifyd insmod install ionice iorenice kill
    killall load_policy ln log logger logname losetup ls lsattr lsmod lsof
    lspci lsusb md5sum memeater mkdir mkfifo mknod mkswap mktemp microcom
    modinfo more mount mountpoint mv nc netcat netstat nice nl nohup nproc
    nsenter od paste patch pgrep pidof pkill pmap printenv printf ps pwd
    readelf readlink realpath renice restorecon rm rmdir rmmod rtcwake runcon
    sed sendevent seq setenforce setfattr setsid sha1sum sha224sum sha256sum
    sha384sum sha512sum sleep sort split stat strings stty swapoff swapon sync
    sysctl tac tail tar taskset tee test time timeout top touch tr true
    truncate tty uclampset ulimit umount uname uniq unix2dos unlink unshare
    uptime usleep uudecode uuencode uuidgen vi vmstat watch wc which whoami
    xargs xxd yes zcat)
add_custom_target(android_root_toybox ALL
    COMMAND "${CMAKE_COMMAND}" -E copy $<TARGET_FILE:toybox>
        "${ROOT}/system/bin/toybox"
    COMMAND sh -c
        "cd \"$0\" && ln -sf toybox '[' && for n; do ln -sf toybox \"$n\"; done"
        "${ROOT}/system/bin" ${TOYBOX_LINKS}
    DEPENDS toybox VERBATIM)
add_dependencies(android_root_toybox android_root_platform)
