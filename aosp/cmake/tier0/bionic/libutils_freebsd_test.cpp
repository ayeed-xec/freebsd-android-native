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

// androidSetThreadName() in the bionic_tests jail.  libutils names the
// calling thread with prctl(PR_SET_NAME), which bionic-freebsd maps to
// thr_set_name(2), and the name reads back with pthread_getname_np().

#include <pthread.h>

#include <string>

#include <gtest/gtest.h>
#include <utils/AndroidThreads.h>

static std::string ThreadName() {
  char name[16];
  EXPECT_EQ(0, pthread_getname_np(pthread_self(), name, sizeof(name)));
  return name;
}

TEST(libutils_freebsd, set_thread_name) {
  androidSetThreadName("short name");
  EXPECT_EQ("short name", ThreadName());
}

// A long name with a dot and no '@', such as a Java class name, keeps its
// last 15 characters.
TEST(libutils_freebsd, set_thread_name_tail) {
  androidSetThreadName("com.example.ThreadNameTest");
  EXPECT_EQ(".ThreadNameTest", ThreadName());
}

// Other long names keep their first 15 characters, as the kernel cuts them.
TEST(libutils_freebsd, set_thread_name_head) {
  androidSetThreadName("abcdefghijklmnopqrstuvwxyz");
  EXPECT_EQ("abcdefghijklmno", ThreadName());
}
