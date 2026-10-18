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

// propd [property_contexts ...]
//
// The property service of a jail that has no Android init.  It must start as root, before
// any other process of the jail, with an empty /dev/__properties__ and /dev/socket.  It
// writes property_info from the property_contexts files, makes the property area with
// bionic's own code, loads /system/build.prop as init does, and answers PROP_MSG_SETPROP2
// requests on /dev/socket/property_service.  Then it drops to AID_NOBODY and goes to the
// background; the area stays mapped for writing.
//
// There is no SELinux, so a context only selects the file of the area that holds a property,
// and every process of the jail may set any property.  ro.* properties can be set once.
// ctl.* requests fail, because there are no services to control.  Nothing is persistent.

#include <ctype.h>
#include <err.h>
#include <errno.h>
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/system_properties.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#include <map>
#include <string>
#include <vector>

#include <android-base/file.h>
#include <android-base/strings.h>
#include <android-base/unique_fd.h>
#include <private/android_filesystem_config.h>
#include <property_info_serializer/property_info_serializer.h>

using android::base::unique_fd;
using android::properties::BuildTrie;
using android::properties::ParsePropertyInfoFile;
using android::properties::PropertyInfoEntry;

namespace {

constexpr char kTreeFile[] = PROP_DIRNAME "/property_info";
constexpr char kSocketPath[] = "/dev/socket/" PROP_SERVICE_NAME;
constexpr char kBuildPropFile[] = "/system/build.prop";
constexpr char kDefaultContext[] = "u:object_r:default_prop:s0";

// The limits of init: a client gets 5 seconds for its request, and a string has at most
// 0xffff bytes.
constexpr int kRequestTimeoutMs = 5000;
constexpr uint32_t kMaxStringLength = 0xffff;

void WritePropertyInfo(int count, char** files) {
    std::vector<PropertyInfoEntry> entries;
    for (int i = 0; i < count; i++) {
        std::string contents;
        if (!android::base::ReadFileToString(files[i], &contents)) err(1, "%s", files[i]);
        std::vector<std::string> errors;
        ParsePropertyInfoFile(contents, true, &entries, &errors);
        for (const auto& error : errors) warnx("%s: %s", files[i], error.c_str());
    }

    std::string trie, error;
    if (!BuildTrie(entries, kDefaultContext, "string", &trie, &error)) {
        errx(1, "cannot serialize the property contexts: %s", error.c_str());
    }
    if (!android::base::WriteStringToFile(trie, kTreeFile, 0444, AID_ROOT, AID_ROOT, false)) {
        err(1, "%s", kTreeFile);
    }
}

int CreateSocket() {
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd == -1) err(1, "socket");

    sockaddr_un addr = {};
    addr.sun_family = AF_UNIX;
    strlcpy(addr.sun_path, kSocketPath, sizeof(addr.sun_path));
    // Clients connect as any user.  Bind with a closed mode first, so that the socket never
    // has a mode other than 0700 or 0666.
    mode_t mask = umask(0077);
    if (bind(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == -1) {
        err(1, "%s", kSocketPath);
    }
    umask(mask);
    if (chmod(kSocketPath, 0666) == -1) err(1, "%s", kSocketPath);
    if (listen(fd, 8) == -1) err(1, "listen");
    return fd;
}

int RemainingMs(const timespec& deadline) {
    timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    int64_t ms = (deadline.tv_sec - now.tv_sec) * 1000 + (deadline.tv_nsec - now.tv_nsec) / 1000000;
    return ms > 0 ? static_cast<int>(ms) : 0;
}

bool RecvAll(int fd, void* buf, size_t len, const timespec& deadline) {
    char* p = static_cast<char*>(buf);
    while (len > 0) {
        pollfd pfd = {.fd = fd, .events = POLLIN};
        int ms = RemainingMs(deadline);
        if (ms == 0) return false;
        int n = poll(&pfd, 1, ms);
        if (n == -1 && errno == EINTR) continue;
        if (n != 1) return false;
        ssize_t r = recv(fd, p, len, MSG_DONTWAIT);
        if (r == -1 && (errno == EINTR || errno == EAGAIN)) continue;
        if (r <= 0) return false;
        p += r;
        len -= r;
    }
    return true;
}

bool RecvString(int fd, std::string* s, const timespec& deadline) {
    uint32_t len;
    if (!RecvAll(fd, &len, sizeof(len), deadline) || len > kMaxStringLength) return false;
    s->resize(len);
    return RecvAll(fd, s->data(), len, deadline);
}

bool IsNameChar(char c) {
    return isalnum(static_cast<unsigned char>(c)) || c == '_' || c == '-' || c == '@' || c == ':';
}

// Words of letters, digits and "_-@:", joined by single dots.
bool IsLegalName(const std::string& name) {
    if (name.empty() || name.front() == '.' || name.back() == '.') return false;
    for (size_t i = 0; i < name.size(); i++) {
        if (name[i] == '.') {
            if (name[i - 1] == '.') return false;
        } else if (!IsNameChar(name[i])) {
            return false;
        }
    }
    return true;
}

// Only ro.* properties take values of PROP_VALUE_MAX bytes or more.  A value must be
// UTF-8, and bionic's mbstowcs() always decodes UTF-8.
bool IsLegalValue(const std::string& name, const std::string& value) {
    if (value.size() >= PROP_VALUE_MAX && !name.starts_with("ro.")) return false;
    if (value.find('\0') != std::string::npos) return false;
    return mbstowcs(nullptr, value.c_str(), 0) != static_cast<size_t>(-1);
}

uint32_t SetProperty(const std::string& name, const std::string& value) {
    if (!IsLegalName(name)) return PROP_ERROR_INVALID_NAME;
    if (name.starts_with("ctl.")) return PROP_ERROR_HANDLE_CONTROL_MESSAGE;
    if (!IsLegalValue(name, value)) return PROP_ERROR_INVALID_VALUE;

    prop_info* pi = const_cast<prop_info*>(__system_property_find(name.c_str()));
    if (pi != nullptr) {
        if (name.starts_with("ro.")) return PROP_ERROR_READ_ONLY_PROPERTY;
        if (__system_property_update(pi, value.c_str(), value.size()) != 0) {
            return PROP_ERROR_SET_FAILED;
        }
    } else if (__system_property_add(name.c_str(), name.size(), value.c_str(), value.size()) !=
               0) {
        return PROP_ERROR_SET_FAILED;
    }
    return PROP_SUCCESS;
}

// A property file has init's format: one "name=value" a line, with the white space around the
// name and the value removed, and "#" comment lines.  A later line for the same name wins.  The
// names that init refuses in a property file are refused here too.
void LoadProperties(const char* path) {
    std::string contents;
    if (!android::base::ReadFileToString(path, &contents)) {
        warn("cannot read properties from %s", path);
        return;
    }

    std::map<std::string, std::string> properties;
    for (const auto& line : android::base::Split(contents, "\n")) {
        std::string entry = android::base::Trim(line);
        if (entry.empty() || entry.front() == '#') continue;
        if (entry.starts_with("import ")) {
            warnx("%s: import is not supported: %s", path, entry.c_str());
            continue;
        }
        size_t eq = entry.find('=');
        if (eq == std::string::npos) continue;
        std::string name = android::base::Trim(entry.substr(0, eq));
        std::string value = android::base::Trim(entry.substr(eq + 1));
        if (name.starts_with("ctl.") || name == "sys.powerctl" ||
            name == "selinux.restorecon_recursive") {
            warnx("%s: ignoring disallowed property %s", path, name.c_str());
            continue;
        }
        properties[name] = value;
    }

    for (const auto& [name, value] : properties) {
        if (uint32_t result = SetProperty(name, value); result != PROP_SUCCESS) {
            warnx("%s: cannot set %s to \"%s\": error 0x%x", path, name.c_str(), value.c_str(),
                  result);
        }
    }
}

// One request per connection, as the client in bionic sends it: the command, the name and
// the value, each string with its length first.  The answer is one result code.
void HandleConnection(int listen_fd) {
    unique_fd fd(accept4(listen_fd, nullptr, nullptr, SOCK_CLOEXEC));
    if (fd == -1) return;

    timespec deadline;
    clock_gettime(CLOCK_MONOTONIC, &deadline);
    deadline.tv_sec += kRequestTimeoutMs / 1000;

    uint32_t cmd, result;
    std::string name, value;
    if (!RecvAll(fd.get(), &cmd, sizeof(cmd), deadline)) {
        result = PROP_ERROR_READ_CMD;
    } else if (cmd != PROP_MSG_SETPROP2) {
        result = PROP_ERROR_INVALID_CMD;
    } else if (!RecvString(fd.get(), &name, deadline) || !RecvString(fd.get(), &value, deadline)) {
        result = PROP_ERROR_READ_DATA;
    } else {
        result = SetProperty(name, value);
    }
    send(fd.get(), &result, sizeof(result), MSG_NOSIGNAL);
}

}  // namespace

int main(int argc, char** argv) {
    if (getuid() != 0) errx(1, "must start as root");

    WritePropertyInfo(argc - 1, argv + 1);
    // This also tries to put SELinux labels on the new files and returns -1 when that fails,
    // which it always does here.  Adding the first property shows whether the area works.
    __system_property_area_init();
    if (SetProperty("ro.property_service.version", "2") != PROP_SUCCESS) {
        errx(1, "cannot make the property area in %s", PROP_DIRNAME);
    }
    LoadProperties(kBuildPropFile);

    int listen_fd = CreateSocket();
    if (setgroups(0, nullptr) == -1 || setgid(AID_NOBODY) == -1 || setuid(AID_NOBODY) == -1) {
        err(1, "cannot drop privileges");
    }
    // The parent exits only now, so whoever started us can use the properties at once.
    if (daemon(0, 0) == -1) err(1, "daemon");

    for (;;) HandleConnection(listen_fd);
}
