/*
 * Copyright (c) 2026 Ayeed Shaikh <Ayeed.AI10@race.reva.edu.in>
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

// libselinux in the bionic_tests jail.  FreeBSD has no selinuxfs, so
// libselinux finds no SELinux mount and works as on a Linux kernel without
// SELinux: it reports SELinux disabled, and the calls that need selinuxfs
// or /proc/<pid>/attr fail with ENOENT.  The file_contexts backend and
// pcre2 work as usual.

#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>

#include <string>

#include <android-base/file.h>
#include <gtest/gtest.h>
#include <selinux/android.h>
#include <selinux/avc.h>
#include <selinux/label.h>
#include <selinux/selinux.h>

TEST(libselinux_freebsd, is_selinux_enabled) {
  EXPECT_EQ(0, is_selinux_enabled());
}

TEST(libselinux_freebsd, security_getenforce) {
  errno = 0;
  EXPECT_EQ(-1, security_getenforce());
  EXPECT_EQ(ENOENT, errno);
}

TEST(libselinux_freebsd, selinux_status_open) {
  errno = 0;
  EXPECT_EQ(-1, selinux_status_open(1));
  EXPECT_EQ(ENOENT, errno);
}

TEST(libselinux_freebsd, selinux_check_access) {
  EXPECT_EQ(0, selinux_check_access("u:r:shell:s0", "u:object_r:system_file:s0",
                                    "file", "read", nullptr));
}

TEST(libselinux_freebsd, android_restorecon_and_setcontext) {
  TemporaryDir dir;
  EXPECT_EQ(0, selinux_android_restorecon(dir.path, SELINUX_ANDROID_RESTORECON_RECURSE));
  EXPECT_EQ(0, selinux_android_setcontext(getuid(), false, "default", "com.example.test"));
}

TEST(libselinux_freebsd, getcon) {
  char* con = nullptr;
  errno = 0;
  EXPECT_EQ(-1, getcon(&con));
  EXPECT_EQ(ENOENT, errno);
  EXPECT_EQ(nullptr, con);
}

TEST(libselinux_freebsd, getfilecon_no_label) {
  TemporaryFile tf;
  char* con = nullptr;
  errno = 0;
  EXPECT_EQ(-1, getfilecon(tf.path, &con));
  // bionic-freebsd keeps "security.selinux" in the system extattr name
  // space, which needs PRIV_VFS_EXTATTR_SYSTEM.  The jail has no
  // allow.extattr, so even root gets EPERM.  Linux gives ENODATA.
  EXPECT_EQ(EPERM, errno);
  EXPECT_EQ(nullptr, con);
}

TEST(libselinux_freebsd, file_contexts_lookup) {
  std::string path =
      android::base::GetExecutableDirectory() + "/libselinux_freebsd_test.file_contexts";
  struct selinux_opt opts[] = {{SELABEL_OPT_PATH, path.c_str()}};
  struct selabel_handle* handle = selabel_open(SELABEL_CTX_FILE, opts, 1);
  ASSERT_NE(nullptr, handle);

  char* con = nullptr;
  ASSERT_EQ(0, selabel_lookup(handle, &con, "/data/local/tmp/file", S_IFREG));
  EXPECT_STREQ("u:object_r:shell_data_file:s0", con);
  freecon(con);

  con = nullptr;
  ASSERT_EQ(0, selabel_lookup(handle, &con, "/data/system", S_IFDIR));
  EXPECT_STREQ("u:object_r:system_data_file:s0", con);
  freecon(con);

  selabel_close(handle);
}
