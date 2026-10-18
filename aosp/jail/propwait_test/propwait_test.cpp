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

// propwait_test [rounds]
// propwait_test -s [iterations [seed]]
//
// Checks that a process with the read-only property area wakes up when another process sets
// a property.  A child waits for debug.propwait with __system_property_wait().  The
// parent sets the property with __system_property_set(), so each change goes through the
// property service, as on a device.  In each round the parent waits until the child is
// ready, sleeps 10ms so that the child really waits, and sets the value to the time of its
// CLOCK_MONOTONIC clock in nanoseconds.  The child reads the clock when the wait returns.
// The difference is the wake latency; it includes the trip through the property service.
//
// The test fails when the page of the property can be made writable, when a wait with a
// timeout does not end in time, when the child misses a change, or when the child uses more
// than 10% of a CPU while it waits.
//
// With -s it is a stress test with six readers that wait at the same time.  Readers 0 to 2
// each wait for their own property, debug.propstress.0 to .2.  Readers 3 to 5 wait for
// the global serial (__system_property_wait() with no prop_info) and need all three.  Three
// setters each change one of the properties through the property service.  In each
// iteration the parent waits until all readers are ready, sleeps for a random time of up to
// 2ms and starts the setters.  Each setter sleeps for a random time of up to 500us and sets
// its property to the iteration and the time.  The seed of the random times is printed, so
// a run can be done again.
//
// A lost wakeup is a wait that times out although a setter finished a change at least 100ms
// before the end of the wait, and the reader had not seen the change before the wait.  A
// hang is a wait that returns more than 500ms after its timeout, or a reader or setter that
// does not finish.  At the end each reader does a 50ms wait with no change, which must time
// out.  The stress fails on a lost wakeup, a hang or a timeout, or when a reader uses more
// than 10% of a CPU while it waits.

#include <err.h>
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/system_properties.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <algorithm>
#include <string>
#include <vector>

namespace {

constexpr char kName[] = "debug.propwait";
constexpr int kDefaultRounds = 100;
constexpr int kMaxRounds = 1000;
constexpr long kSetDelayNs = 10 * 1000 * 1000;
constexpr time_t kWaitTimeoutS = 5;
constexpr long kShortTimeoutNs = 50 * 1000 * 1000;
constexpr unsigned kAlarmS = 60;
// The child may use this share of the time that it waits, in percent.
constexpr int64_t kMaxCpuPercent = 10;

constexpr char kStressPrefix[] = "debug.propstress.";
constexpr int kStressReaders = 6;
// Readers below kStressProps wait for property k; the other readers wait for the global serial.
constexpr int kStressProps = 3;
constexpr time_t kStressTimeoutS = 2;
// A reader gives up an iteration after this many timeouts in a row.
constexpr int kMaxTimeoutsInRow = 3;
constexpr int64_t kLateNs = 100 * 1000 * 1000;
constexpr int64_t kHangSlackNs = 500 * 1000 * 1000;
constexpr int kReadyTimeoutMs = 30 * 1000;
constexpr long kRoundJitterUs = 2000;
constexpr long kSetJitterUs = 500;

// The child writes its results here, in a shared anonymous mapping.
struct Results {
    int woken;
    int timeouts;
    int64_t wait_ns;
    int64_t latency_ns[kMaxRounds];
};

// Each stress reader writes its own entry.
struct ReaderStats {
    int rounds;
    int waits;
    int timeouts;
    int lost;
    int hangs;
    bool final_woke;
    int64_t final_wait_ns;
    int64_t wait_ns;
    int64_t latency_ns[kMaxRounds];
};

struct StressResults {
    ReaderStats reader[kStressReaders];
    // Written by the setters: the time when __system_property_set() returned, and how long it
    // took.  A done time of 0 means that the change is not finished.
    int64_t done_ns[kStressProps][kMaxRounds];
    int64_t set_ns[kStressProps][kMaxRounds];
};

int64_t NowNs() {
    timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

void SleepUs(long us) {
    timespec ts = {us / 1000000, (us % 1000000) * 1000};
    nanosleep(&ts, nullptr);
}

// xorshift64.  It is enough for the random sleeps, and a seed gives the same sleeps again.
uint64_t NextRandom(uint64_t* state) {
    uint64_t x = *state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    return *state = x;
}

int64_t CpuNs(const rusage& ru) {
    return (ru.ru_utime.tv_sec + ru.ru_stime.tv_sec) * 1000000000LL +
           (ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) * 1000LL;
}

// Clients map the area from an O_RDONLY descriptor, so the page cannot become writable.
// A writable page would hide the problem: the kernel can always wait on it.  Returns the
// errno of mprotect().
int CheckReadOnly(const prop_info* pi, const char* name) {
    long page = sysconf(_SC_PAGESIZE);
    void* page_start = reinterpret_cast<void*>(reinterpret_cast<uintptr_t>(pi) & ~(page - 1));
    if (mprotect(page_start, page, PROT_READ | PROT_WRITE) == 0) {
        mprotect(page_start, page, PROT_READ);
        errx(1, "the page of %s can be made writable", name);
    }
    return errno;
}

std::string ReadValue(const prop_info* pi) {
    std::string value;
    __system_property_read_callback(
            pi,
            [](void* cookie, const char*, const char* v, uint32_t) {
                *static_cast<std::string*>(cookie) = v;
            },
            &value);
    return value;
}

// The child.  It tells the parent through ready_fd that it is about to wait.  A wait can
// return while the service is in the middle of an update, and the old value is still there;
// then it waits again.
[[noreturn]] void Reader(const prop_info* pi, int rounds, int ready_fd, Results* r) {
    timespec timeout = {kWaitTimeoutS, 0};
    std::string old_value = ReadValue(pi);
    for (int i = 0; i < rounds; i++) {
        uint32_t serial = __system_property_serial(pi);
        if (write(ready_fd, "", 1) != 1) _exit(1);

        int64_t start = NowNs(), woke = 0;
        std::string value;
        bool timed_out = false;
        do {
            if (!__system_property_wait(pi, serial, &serial, &timeout)) {
                timed_out = true;
                break;
            }
            woke = NowNs();
            value = ReadValue(pi);
        } while (value == old_value);
        if (timed_out) {
            r->timeouts++;
            old_value = ReadValue(pi);
            continue;
        }
        r->wait_ns += woke - start;
        r->latency_ns[r->woken++] = woke - strtoll(value.c_str(), nullptr, 10);
        old_value = value;
    }
    _exit(0);
}

int64_t Percentile(const std::vector<int64_t>& sorted, int percent) {
    if (sorted.empty()) return 0;
    return sorted[std::min(sorted.size() - 1, sorted.size() * percent / 100)];
}

void PrintLatency(const char* what, std::vector<int64_t>* ns) {
    std::sort(ns->begin(), ns->end());
    printf("%s: median %lld us, 90th percentile %lld us, maximum %lld us\n", what,
           static_cast<long long>(Percentile(*ns, 50) / 1000),
           static_cast<long long>(Percentile(*ns, 90) / 1000),
           static_cast<long long>(ns->empty() ? 0 : ns->back() / 1000));
}

std::string StressName(int p) {
    return kStressPrefix + std::to_string(p);
}

// A stress value is "<iteration> <CLOCK_MONOTONIC time of the setter in ns>".
bool ParseStressValue(const std::string& value, int* round, int64_t* sent) {
    char* end;
    long r = strtol(value.c_str(), &end, 10);
    if (end == value.c_str() || *end != ' ') return false;
    *round = static_cast<int>(r);
    *sent = strtoll(end + 1, nullptr, 10);
    return true;
}

uint32_t StressSerial(const prop_info* pi) {
    return pi != nullptr ? __system_property_serial(pi) : __system_property_area_serial();
}

// Reads n bytes from fd.  Returns false when they do not come in timeout_ms.
bool ReadBytes(int fd, int n, int timeout_ms) {
    int64_t deadline = NowNs() + timeout_ms * 1000000LL;
    char buf[kStressReaders];
    while (n > 0) {
        int64_t left = deadline - NowNs();
        if (left <= 0) return false;
        pollfd pfd = {fd, POLLIN, 0};
        int rc = poll(&pfd, 1, static_cast<int>(left / 1000000) + 1);
        if (rc == -1 && errno == EINTR) continue;
        if (rc <= 0) return false;
        ssize_t got = read(fd, buf, std::min(n, kStressReaders));
        if (got <= 0) return false;
        n -= got;
    }
    return true;
}

// A stress reader.  In each iteration it reads the serial, tells the parent that it is
// ready, and then looks at the values.  A change that it does not see there comes after
// the serial, so the wait must return for it.  After the last iteration it waits for the
// parent once more, then does a short wait with no change.
[[noreturn]] void StressReader(int k, const prop_info* const* props, int rounds, int ready_fd,
                               int final_fd, StressResults* r) {
    ReaderStats* st = &r->reader[k];
    const prop_info* pi = k < kStressProps ? props[k] : nullptr;
    int first = pi != nullptr ? k : 0;
    int last = pi != nullptr ? k + 1 : kStressProps;

    alarm(kAlarmS);
    for (int i = 0; i < rounds; i++) {
        uint32_t serial = StressSerial(pi);
        if (write(ready_fd, "", 1) != 1) _exit(1);

        bool seen[kStressProps] = {};
        int64_t newest_sent = 0;
        int timeouts_in_row = 0;
        while (timeouts_in_row < kMaxTimeoutsInRow) {
            int missing = 0;
            for (int p = first; p < last; p++) {
                int round;
                int64_t sent;
                if (!seen[p] && ParseStressValue(ReadValue(props[p]), &round, &sent) &&
                    round == i) {
                    seen[p] = true;
                    newest_sent = std::max(newest_sent, sent);
                }
                if (!seen[p]) missing++;
            }
            if (missing == 0) {
                st->latency_ns[st->rounds++] = NowNs() - newest_sent;
                break;
            }

            timespec timeout = {kStressTimeoutS, 0};
            int64_t start = NowNs();
            bool woke = __system_property_wait(pi, serial, &serial, &timeout);
            int64_t end = NowNs();
            st->waits++;
            st->wait_ns += end - start;
            if (woke) {
                timeouts_in_row = 0;
                continue;
            }
            timeouts_in_row++;
            if (end - start > kStressTimeoutS * 1000000000LL + kHangSlackNs) st->hangs++;
            bool lost = false;
            for (int p = first; p < last; p++) {
                int64_t done = __atomic_load_n(&r->done_ns[p][i], __ATOMIC_ACQUIRE);
                if (!seen[p] && done != 0 && done < end - kLateNs) lost = true;
            }
            if (lost) {
                st->lost++;
            } else {
                st->timeouts++;
            }
            serial = StressSerial(pi);
        }
    }

    // The parent sends the last byte when all setters have ended, so nothing changes now.
    char c;
    if (write(ready_fd, "", 1) != 1 || read(final_fd, &c, 1) != 1) _exit(1);
    timespec timeout = {0, kShortTimeoutNs};
    uint32_t serial = StressSerial(pi);
    int64_t start = NowNs();
    st->final_woke = __system_property_wait(pi, serial, &serial, &timeout);
    st->final_wait_ns = NowNs() - start;
    _exit(0);
}

// A stress setter.  It changes property k once for each byte from the parent.
[[noreturn]] void StressSetter(int k, int rounds, int go_fd, uint64_t seed, StressResults* r) {
    std::string name = StressName(k);
    uint64_t random_state = seed + k + 1;

    alarm(kAlarmS);
    for (int i = 0; i < rounds; i++) {
        char c;
        if (read(go_fd, &c, 1) != 1) _exit(1);
        SleepUs(static_cast<long>(NextRandom(&random_state) % (kSetJitterUs + 1)));
        int64_t sent = NowNs();
        std::string value = std::to_string(i) + " " + std::to_string(sent);
        if (__system_property_set(name.c_str(), value.c_str()) != 0) _exit(1);
        int64_t done = NowNs();
        r->set_ns[k][i] = done - sent;
        __atomic_store_n(&r->done_ns[k][i], done, __ATOMIC_RELEASE);
    }
    _exit(0);
}

// Waits for a child and returns its CPU time.  A child that its own alarm stopped is a hang.
int64_t Reap(pid_t pid, const std::string& what, int* hangs, std::string* failure) {
    int status;
    rusage ru;
    if (wait4(pid, &status, 0, &ru) == -1) err(1, "wait4");
    if (WIFSIGNALED(status) && WTERMSIG(status) == SIGALRM) {
        (*hangs)++;
        if (failure->empty()) *failure = what + " did not finish";
    } else if ((!WIFEXITED(status) || WEXITSTATUS(status) != 0) && failure->empty()) {
        *failure = what + " failed";
    }
    return CpuNs(ru);
}

int Stress(int argc, char** argv) {
    int rounds = argc > 1 ? atoi(argv[1]) : kDefaultRounds;
    if (rounds < 1 || rounds > kMaxRounds) errx(1, "iterations must be 1 to %d", kMaxRounds);
    uint64_t seed = argc > 2 ? strtoull(argv[2], nullptr, 0) : static_cast<uint64_t>(NowNs());
    if (seed == 0) seed = 1;

    const prop_info* props[kStressProps];
    for (int p = 0; p < kStressProps; p++) {
        std::string name = StressName(p);
        if (__system_property_set(name.c_str(), "-1 0") != 0) {
            errx(1, "cannot set %s", name.c_str());
        }
        props[p] = __system_property_find(name.c_str());
        if (props[p] == nullptr) errx(1, "cannot find %s", name.c_str());
    }
    int ro_errno = CheckReadOnly(props[0], StressName(0).c_str());

    void* shared = mmap(nullptr, sizeof(StressResults), PROT_READ | PROT_WRITE,
                        MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (shared == MAP_FAILED) err(1, "mmap");
    StressResults* r = static_cast<StressResults*>(shared);

    // A setter that stopped makes the write of its byte fail with EPIPE.
    signal(SIGPIPE, SIG_IGN);
    alarm(2 * kAlarmS);
    int ready[2], final_go[2];
    if (pipe(ready) == -1 || pipe(final_go) == -1) err(1, "pipe");
    pid_t readers[kStressReaders];
    for (int k = 0; k < kStressReaders; k++) {
        if ((readers[k] = fork()) == -1) err(1, "fork");
        if (readers[k] == 0) {
            close(ready[0]);
            close(final_go[1]);
            StressReader(k, props, rounds, ready[1], final_go[0], r);
        }
    }
    close(ready[1]);
    close(final_go[0]);
    pid_t setters[kStressProps];
    int go[kStressProps];
    for (int k = 0; k < kStressProps; k++) {
        int fds[2];
        if (pipe(fds) == -1) err(1, "pipe");
        if ((setters[k] = fork()) == -1) err(1, "fork");
        if (setters[k] == 0) {
            for (int j = 0; j < k; j++) close(go[j]);
            close(fds[1]);
            StressSetter(k, rounds, fds[0], seed, r);
        }
        close(fds[0]);
        go[k] = fds[1];
    }

    int hangs = 0;
    std::string failure;
    uint64_t random_state = seed;
    int64_t start = NowNs();
    for (int i = 0; i < rounds && failure.empty(); i++) {
        if (!ReadBytes(ready[0], kStressReaders, kReadyTimeoutMs)) {
            hangs++;
            failure = "the readers were not ready in iteration " + std::to_string(i);
            break;
        }
        SleepUs(static_cast<long>(NextRandom(&random_state) % (kRoundJitterUs + 1)));
        for (int k = 0; k < kStressProps; k++) {
            if (write(go[k], "", 1) != 1) {
                failure = "setter " + std::to_string(k) + " stopped";
                break;
            }
        }
    }
    for (int k = 0; k < kStressProps; k++) close(go[k]);
    if (failure.empty() && !ReadBytes(ready[0], kStressReaders, kReadyTimeoutMs)) {
        hangs++;
        failure = "the readers did not finish the last iteration";
    }
    int64_t elapsed_ns = NowNs() - start;
    if (!failure.empty()) {
        for (pid_t pid : setters) kill(pid, SIGKILL);
    }
    for (int k = 0; k < kStressProps; k++) {
        Reap(setters[k], "setter " + std::to_string(k), &hangs, &failure);
    }
    if (failure.empty()) {
        char bytes[kStressReaders] = {};
        if (write(final_go[1], bytes, sizeof(bytes)) != sizeof(bytes)) err(1, "write");
    } else {
        for (pid_t pid : readers) kill(pid, SIGKILL);
    }
    int64_t cpu_ns[kStressReaders];
    for (int k = 0; k < kStressReaders; k++) {
        cpu_ns[k] = Reap(readers[k], "reader " + std::to_string(k), &hangs, &failure);
    }

    printf("%d iterations, %d readers (%d on a property, %d on the global serial), %d setters, "
           "seed %#llx\n", rounds, kStressReaders, kStressProps, kStressReaders - kStressProps,
           kStressProps, static_cast<unsigned long long>(seed));
    printf("page of %s is read-only (mprotect: %s)\n", StressName(0).c_str(),
           strerror(ro_errno));
    printf("iterations took %lld ms\n", static_cast<long long>(elapsed_ns / 1000000));

    int lost = 0, timeouts = 0, short_rounds = 0, final_bad = 0;
    int64_t final_min = INT64_MAX, final_max = 0, cpu_total = 0, wait_total = 0;
    bool cpu_high = false;
    std::vector<int64_t> prop_latency, global_latency, set_ns;
    for (int k = 0; k < kStressReaders; k++) {
        const ReaderStats* st = &r->reader[k];
        int64_t wait_ns = st->wait_ns + st->final_wait_ns;
        int64_t permille = wait_ns > 0 ? cpu_ns[k] * 1000 / wait_ns : 0;
        std::string what = k < kStressProps ? StressName(k) : "global serial";
        printf("reader %d, %s: %d of %d iterations, %d waits, %d lost, %d hangs, %d timeouts, "
               "CPU %lld us in %lld ms of waiting (%lld.%lld%%)\n", k, what.c_str(), st->rounds,
               rounds, st->waits, st->lost, st->hangs, st->timeouts,
               static_cast<long long>(cpu_ns[k] / 1000), static_cast<long long>(wait_ns / 1000000),
               static_cast<long long>(permille / 10), static_cast<long long>(permille % 10));
        lost += st->lost;
        hangs += st->hangs;
        timeouts += st->timeouts;
        if (st->rounds != rounds) short_rounds++;
        if (permille > kMaxCpuPercent * 10) cpu_high = true;
        cpu_total += cpu_ns[k];
        wait_total += wait_ns;
        std::vector<int64_t>* latency = k < kStressProps ? &prop_latency : &global_latency;
        latency->insert(latency->end(), st->latency_ns, st->latency_ns + st->rounds);
        if (failure.empty()) {
            if (st->final_woke || st->final_wait_ns < kShortTimeoutNs) {
                final_bad++;
            } else if (st->final_wait_ns > kShortTimeoutNs + kHangSlackNs) {
                hangs++;
            }
            final_min = std::min(final_min, st->final_wait_ns);
            final_max = std::max(final_max, st->final_wait_ns);
        }
    }
    for (int p = 0; p < kStressProps; p++) {
        for (int i = 0; i < rounds; i++) {
            if (r->done_ns[p][i] != 0) set_ns.push_back(r->set_ns[p][i]);
        }
    }
    int64_t permille = wait_total > 0 ? cpu_total * 1000 / wait_total : 0;

    PrintLatency("wake latency, property readers", &prop_latency);
    PrintLatency("wake latency, global readers", &global_latency);
    PrintLatency("__system_property_set()", &set_ns);
    printf("CPU of all readers: %lld us in %lld ms of waiting (%lld.%lld%%)\n",
           static_cast<long long>(cpu_total / 1000), static_cast<long long>(wait_total / 1000000),
           static_cast<long long>(permille / 10), static_cast<long long>(permille % 10));
    if (failure.empty()) {
        printf("wait with a %ld ms timeout and no change: %d of %d readers false after %lld to "
               "%lld ms\n", kShortTimeoutNs / 1000000, kStressReaders - final_bad,
               kStressReaders, static_cast<long long>(final_min / 1000000),
               static_cast<long long>(final_max / 1000000));
    }
    printf("lost wakeups: %d, hangs: %d\n", lost, hangs);

    if (!failure.empty()) errx(1, "FAIL: %s", failure.c_str());
    if (lost != 0 || hangs != 0) errx(1, "FAIL: %d lost wakeups, %d hangs", lost, hangs);
    if (short_rounds != 0 || timeouts != 0) {
        errx(1, "FAIL: %d readers missed iterations, %d waits timed out", short_rounds, timeouts);
    }
    if (final_bad != 0) errx(1, "FAIL: %d waits with no change did not time out", final_bad);
    if (cpu_high) {
        errx(1, "FAIL: a reader used more than %lld%% of a CPU while it waited",
             static_cast<long long>(kMaxCpuPercent));
    }
    printf("PASS\n");
    return 0;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc > 1 && strcmp(argv[1], "-s") == 0) return Stress(argc - 1, argv + 1);

    int rounds = argc > 1 ? atoi(argv[1]) : kDefaultRounds;
    if (rounds < 1 || rounds > kMaxRounds) errx(1, "rounds must be 1 to %d", kMaxRounds);

    if (__system_property_set(kName, "0") != 0) errx(1, "cannot set %s", kName);
    const prop_info* pi = __system_property_find(kName);
    if (pi == nullptr) errx(1, "cannot find %s", kName);
    int ro_errno = CheckReadOnly(pi, kName);

    // A wait with a timeout must end when nobody sets the property.  A wait that spins and
    // never ends is stopped by the alarm.
    alarm(kAlarmS);
    timespec timeout = {0, kShortTimeoutNs};
    uint32_t serial;
    int64_t start = NowNs();
    if (__system_property_wait(pi, __system_property_serial(pi), &serial, &timeout)) {
        errx(1, "FAIL: the wait returned, but nobody set %s", kName);
    }
    int64_t timed_wait_ns = NowNs() - start;
    if (timed_wait_ns < kShortTimeoutNs) errx(1, "FAIL: the wait timed out too early");

    void* shared = mmap(nullptr, sizeof(Results), PROT_READ | PROT_WRITE,
                        MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (shared == MAP_FAILED) err(1, "mmap");
    Results* r = static_cast<Results*>(shared);

    int ready[2];
    if (pipe(ready) == -1) err(1, "pipe");
    pid_t pid = fork();
    if (pid == -1) err(1, "fork");
    if (pid == 0) {
        close(ready[0]);
        Reader(pi, rounds, ready[1], r);
    }
    close(ready[1]);

    std::vector<int64_t> set_ns;
    for (int i = 0; i < rounds; i++) {
        char c;
        if (read(ready[0], &c, 1) != 1) errx(1, "the child stopped after %d rounds", i);
        timespec delay = {0, kSetDelayNs};
        nanosleep(&delay, nullptr);
        int64_t sent = NowNs();
        if (__system_property_set(kName, std::to_string(sent).c_str()) != 0) {
            errx(1, "cannot set %s", kName);
        }
        set_ns.push_back(NowNs() - sent);
    }
    int status;
    rusage ru;
    if (wait4(pid, &status, 0, &ru) == -1) err(1, "wait4");
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) errx(1, "the child failed");
    int64_t cpu_ns = CpuNs(ru);

    std::vector<int64_t> latency(r->latency_ns, r->latency_ns + r->woken);
    std::sort(latency.begin(), latency.end());
    std::sort(set_ns.begin(), set_ns.end());
    int64_t cpu_permille = r->wait_ns > 0 ? cpu_ns * 1000 / r->wait_ns : 0;

    printf("%s: %d rounds, page of the property is read-only (mprotect: %s)\n", kName, rounds,
           strerror(ro_errno));
    printf("wait with a %ld ms timeout and no change: false after %lld ms\n",
           kShortTimeoutNs / 1000000, static_cast<long long>(timed_wait_ns / 1000000));
    printf("woken %d of %d, %d timeouts\n", r->woken, rounds, r->timeouts);
    printf("wake latency: median %lld us, 90th percentile %lld us, maximum %lld us\n",
           static_cast<long long>(Percentile(latency, 50) / 1000),
           static_cast<long long>(Percentile(latency, 90) / 1000),
           static_cast<long long>(latency.empty() ? 0 : latency.back() / 1000));
    printf("__system_property_set(): median %lld us, maximum %lld us\n",
           static_cast<long long>(Percentile(set_ns, 50) / 1000),
           static_cast<long long>(set_ns.back() / 1000));
    printf("child CPU: %lld us in %lld ms of waiting (%lld.%lld%%)\n",
           static_cast<long long>(cpu_ns / 1000), static_cast<long long>(r->wait_ns / 1000000),
           static_cast<long long>(cpu_permille / 10), static_cast<long long>(cpu_permille % 10));

    if (r->woken != rounds) errx(1, "FAIL: %d waits timed out", r->timeouts);
    if (cpu_permille > kMaxCpuPercent * 10) {
        errx(1, "FAIL: the child used more than %lld%% of a CPU while it waited",
             static_cast<long long>(kMaxCpuPercent));
    }
    printf("PASS\n");
    return 0;
}
