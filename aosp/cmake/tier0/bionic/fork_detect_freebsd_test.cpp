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

// BoringSSL's fork detection in the bionic_tests jail.  bionic's fork()
// runs the atfork handlers, but _Fork() and clone() without CLONE_VM do
// not.  There only the MADV_WIPEONFORK page tells BoringSSL that it runs
// in a copy of the address space, so that it reseeds.  Without it, each
// copy draws the same bytes from the same DRBG state.

#if !defined(_GNU_SOURCE)
#define _GNU_SOURCE	// for clone()
#endif

#include <sched.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <vector>

#include <gtest/gtest.h>
#include <openssl/rand.h>

using Block = std::array<uint8_t, 16>;

static int g_pipe[2];

static int DrawInChild(void*) {
  Block b;
  if (RAND_bytes(b.data(), b.size()) != 1 ||
      write(g_pipe[1], b.data(), b.size()) != static_cast<ssize_t>(b.size())) {
    _exit(1);
  }
  _exit(0);
}

// Reads the block of the child and waits for its exit.
static void CollectChild(pid_t pid, std::vector<Block>* blocks) {
  ASSERT_NE(-1, pid);
  Block b;
  ASSERT_EQ(static_cast<ssize_t>(b.size()), read(g_pipe[0], b.data(), b.size()));
  int status;
  ASSERT_EQ(pid, waitpid(pid, &status, 0));
  ASSERT_TRUE(WIFEXITED(status));
  ASSERT_EQ(0, WEXITSTATUS(status));
  blocks->push_back(b);
}

TEST(fork_detect_freebsd, new_address_space) {
  ASSERT_EQ(0, pipe(g_pipe));
  std::vector<Block> blocks(1);
  ASSERT_EQ(1, RAND_bytes(blocks[0].data(), blocks[0].size()));

  for (int i = 0; i < 2; i++) {
    pid_t pid = _Fork();
    if (pid == 0) DrawInChild(nullptr);
    CollectChild(pid, &blocks);
  }
  alignas(16) static char stack[64 * 1024];
  CollectChild(clone(DrawInChild, stack + sizeof(stack), SIGCHLD, nullptr), &blocks);

  blocks.emplace_back();
  ASSERT_EQ(1, RAND_bytes(blocks.back().data(), blocks.back().size()));
  for (size_t i = 0; i < blocks.size(); i++) {
    for (size_t j = i + 1; j < blocks.size(); j++) {
      EXPECT_NE(blocks[i], blocks[j]) << "blocks " << i << " and " << j;
    }
  }
}
