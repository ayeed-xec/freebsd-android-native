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

// svcstart [-s name:type:mode:uid:gid] ... [-g gid[,gid ...]] [-p priority] [-u uid]
//          program [arg ...]
//
// Starts one service of an .rc file in a jail that has no Android init, as init does for a
// service with these options:
//
//   -s name:type:mode:uid:gid  "socket name type mode user group": an AF_UNIX socket of type
//                              stream, dgram or seqpacket, with "+passcred" for SO_PASSCRED,
//                              bound to /dev/socket/<name> with that mode and owner.  The
//                              service gets its descriptor in ANDROID_SOCKET_<name>.
//   -g gid[,gid ...]           "group": the gid, then the supplementary groups.
//   -p priority                "priority": the nice value.
//   -u uid                     "user".
//
// The ids are numbers, because the jail has no user database.  svcstart runs as root.  The
// service runs in a new session, with /dev/null as stdin, stdout and stderr, and svcstart
// exits without waiting for it.  The other service options (capabilities, task_profiles,
// file, onrestart) have no counterpart here.

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#include <string>
#include <vector>

#include <cutils/sockets.h>

namespace {

struct Socket {
    std::string name;
    int fd;
};

[[noreturn]] void Usage() {
    fprintf(stderr,
            "usage: svcstart [-s name:type:mode:uid:gid] ... [-g gid[,gid ...]] [-p priority]\n"
            "                [-u uid] program [arg ...]\n");
    exit(2);
}

long ParseNumber(const std::string& s, int base, long min, long max) {
    char* end;
    errno = 0;
    long n = strtol(s.c_str(), &end, base);
    if (errno != 0 || s.empty() || *end != '\0' || n < min || n > max) Usage();
    return n;
}

std::vector<std::string> Split(const std::string& s, char sep) {
    std::vector<std::string> fields;
    size_t start = 0;
    for (;;) {
        size_t end = s.find(sep, start);
        fields.push_back(s.substr(start, end - start));
        if (end == std::string::npos) return fields;
        start = end + 1;
    }
}

int SocketType(std::string type, bool* passcred) {
    *passcred = false;
    if (size_t plus = type.find('+'); plus != std::string::npos) {
        if (type.substr(plus) != "+passcred") Usage();
        *passcred = true;
        type.resize(plus);
    }
    if (type == "stream") return SOCK_STREAM;
    if (type == "dgram") return SOCK_DGRAM;
    if (type == "seqpacket") return SOCK_SEQPACKET;
    Usage();
}

Socket CreateSocket(const char* spec) {
    std::vector<std::string> f = Split(spec, ':');
    if (f.size() != 5 || f[0].empty() || f[0].find('/') != std::string::npos) Usage();
    bool passcred;
    int type = SocketType(f[1], &passcred);
    mode_t mode = ParseNumber(f[2], 8, 0, 0777);
    uid_t uid = ParseNumber(f[3], 10, 0, INT32_MAX);
    gid_t gid = ParseNumber(f[4], 10, 0, INT32_MAX);

    std::string path = ANDROID_SOCKET_DIR "/" + f[0];
    sockaddr_un addr = {};
    addr.sun_family = AF_UNIX;
    if (strlcpy(addr.sun_path, path.c_str(), sizeof(addr.sun_path)) >= sizeof(addr.sun_path)) {
        errx(1, "%s: name too long", path.c_str());
    }
    int fd = socket(AF_UNIX, type | SOCK_CLOEXEC, 0);
    if (fd == -1) err(1, "socket %s", f[0].c_str());
    if (passcred) {
        int on = 1;
        if (setsockopt(fd, SOL_SOCKET, SO_PASSCRED, &on, sizeof(on)) == -1) {
            err(1, "SO_PASSCRED %s", f[0].c_str());
        }
    }
    if (unlink(path.c_str()) == -1 && errno != ENOENT) err(1, "%s", path.c_str());
    // Bind with a closed mode, so that the socket never has a mode wider than the one asked.
    mode_t mask = umask(0777);
    int rc = bind(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr));
    umask(mask);
    if (rc == -1) err(1, "%s", path.c_str());
    if (lchown(path.c_str(), uid, gid) == -1 || chmod(path.c_str(), mode) == -1) {
        err(1, "%s", path.c_str());
    }
    return {f[0], fd};
}

}  // namespace

int main(int argc, char** argv) {
    std::vector<Socket> sockets;
    std::vector<gid_t> groups;
    bool set_priority = false, set_uid = false;
    int priority = 0;
    uid_t uid = 0;

    int ch;
    while ((ch = getopt(argc, argv, "+g:p:s:u:")) != -1) {
        switch (ch) {
            case 'g':
                for (const auto& g : Split(optarg, ',')) {
                    groups.push_back(ParseNumber(g, 10, 0, INT32_MAX));
                }
                break;
            case 'p':
                priority = ParseNumber(optarg, 10, PRIO_MIN, PRIO_MAX);
                set_priority = true;
                break;
            case 's':
                sockets.push_back(CreateSocket(optarg));
                break;
            case 'u':
                uid = ParseNumber(optarg, 10, 0, INT32_MAX);
                set_uid = true;
                break;
            default:
                Usage();
        }
    }
    argv += optind;
    if (argv[0] == nullptr) Usage();

    pid_t pid = fork();
    if (pid == -1) err(1, "fork");
    if (pid != 0) return 0;

    // The service.
    if (setsid() == -1) err(1, "setsid");
    for (const auto& s : sockets) {
        int flags = fcntl(s.fd, F_GETFD);
        if (flags == -1 || fcntl(s.fd, F_SETFD, flags & ~FD_CLOEXEC) == -1) {
            err(1, "%s", s.name.c_str());
        }
        std::string name = ANDROID_SOCKET_ENV_PREFIX + s.name;
        if (setenv(name.c_str(), std::to_string(s.fd).c_str(), 1) == -1) err(1, "setenv");
    }
    if (set_priority && setpriority(PRIO_PROCESS, 0, priority) == -1) err(1, "setpriority");
    if (!groups.empty() &&
        (setgroups(groups.size() - 1, groups.data() + 1) == -1 || setgid(groups[0]) == -1)) {
        err(1, "groups");
    }
    if (set_uid && setuid(uid) == -1) err(1, "setuid");
    int null = open("/dev/null", O_RDWR | O_CLOEXEC);
    if (null == -1) err(1, "/dev/null");
    if (dup2(null, STDIN_FILENO) == -1 || dup2(null, STDOUT_FILENO) == -1 ||
        dup2(null, STDERR_FILENO) == -1) {
        err(1, "dup2");
    }
    execv(argv[0], argv);
    _exit(127);
}
