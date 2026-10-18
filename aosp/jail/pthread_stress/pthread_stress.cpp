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

// pthread_stress [iterations [seed]]
//
// A stress test of bionic's mutexes, condition variables and rwlocks, which sleep and wake
// through the futex calls on _umtx_op(2).  Each iteration has four phases, and in each phase
// six workers run at the same time:
//
//   mutex      Each worker takes one of four mutexes 300 times: normal, recursive,
//              error-check and priority inheritance.  It counts under the lock and checks that
//              nobody else owns the mutex.
//   cond       Three producers and three consumers pass 200 items each through a queue of two
//              places, with a "not empty" and a "not full" condition variable and
//              pthread_cond_signal().  The consumers check the sum of the items.
//   broadcast  The six workers wait on one condition variable.  The parent waits until all six
//              wait, then wakes them with pthread_cond_broadcast(), 30 times.
//   rwlock     Each worker takes the read lock (3 of 4 times) or the write lock, 300 times.  A
//              writer changes two words, and a reader must see them equal.  The rwlock prefers
//              readers in even iterations and writers in odd ones.
//
// Each phase runs twice: with six threads of one process, which use the private futex calls,
// and with six processes on a shared mapping (PTHREAD_PROCESS_SHARED), which use the shared
// ones.  The objects are made again for each phase.  Each lock or wait picks one of the
// plain call, the CLOCK_MONOTONIC call, the CLOCK_REALTIME call or a trylock loop; the timed
// calls have a 2s timeout.  The condition variables use CLOCK_REALTIME in even iterations and
// CLOCK_MONOTONIC in odd ones.  The seed of the random choices is printed, so a run can be
// done again.
//
// The six workers of a phase wait for one start byte each, so that they begin at the same
// time.  One lock in eight is held for 50us, so that the other workers must sleep on the
// futex.  A lock call that takes more than 20us counts as a lock that waited.  A lock phase
// with no lock that waited, or a condition variable phase with no wait, did not test the wake
// path, and the test fails.
//
// No lock is held for long, so a timed call must not time out.  A timed lock that times out
// while the lock is free (a trylock then gets it) is a lost wakeup.  A timed wait that times
// out although its condition became true at least 100ms before the end of the wait is a lost
// wakeup.  A hang is a timed call that returns more than 500ms after its timeout, or a phase
// that does not end in 10s; with the plain calls a lost wakeup shows up as such a hang.  The
// test fails on a lost wakeup, a hang, any other timeout, a second owner of a lock, or a lost
// count or item.

#include <err.h>
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <algorithm>
#include <string>
#include <vector>

namespace {

constexpr int kDefaultRounds = 100;
constexpr int kMaxRounds = 1000;
constexpr int kWorkers = 6;
constexpr int kMutexKinds = 4;
constexpr int kLockOps = 300;
constexpr int kProducers = 3;
constexpr int kItems = 200;
constexpr int kQueueSize = 2;
constexpr int kBroadcastRounds = 30;
constexpr int kRwlockOps = 300;
constexpr time_t kTimeoutS = 2;
constexpr int64_t kTimeoutNs = kTimeoutS * 1000000000LL;
constexpr int64_t kLateNs = 100 * 1000 * 1000;
constexpr int64_t kHangSlackNs = 500 * 1000 * 1000;
constexpr int kPhaseTimeoutMs = 10 * 1000;
constexpr unsigned kAlarmS = 60;
// One lock in kHoldOneIn is held for kHoldUs, so that the other workers must sleep on it.
constexpr int kHoldOneIn = 8;
constexpr long kHoldUs = 50;
// A lock call that takes longer than this has waited for another owner.
constexpr int64_t kWaitedNs = 20 * 1000;

enum Phase { kMutex, kCond, kBroadcast, kRwlock, kPhases };
constexpr const char* kPhaseName[kPhases] = {"mutex", "cond", "broadcast", "rwlock"};
constexpr const char* kMutexName[kMutexKinds] = {"normal", "recursive", "errorcheck", "pi"};
constexpr const char* kTwoOwners[kMutexKinds] = {
        "two owners of the normal mutex", "two owners of the recursive mutex",
        "two owners of the errorcheck mutex", "two owners of the pi mutex"};

// How a worker takes a lock or waits.
enum How { kPlain, kMonotonic, kRealtime, kTry, kHows };

struct WorkerStats {
    int ops;
    int timed;
    int tries;
    int waited;
    int waits;
    int lost;
    int timeouts;
    int hangs;
    int errors;
    bool aborted;
    int per_mutex[kMutexKinds];
    int64_t item_sum;
    int64_t wake_ns[kBroadcastRounds];
    char error[128];
};

// One mapping for both scopes: threads share it as memory of their process, processes as a
// MAP_SHARED mapping.
struct Shared {
    pthread_mutex_t mutex[kMutexKinds];
    int owner[kMutexKinds];
    int64_t count[kMutexKinds];

    pthread_mutex_t queue_lock;
    pthread_cond_t not_empty;
    pthread_cond_t not_full;
    int queue[kQueueSize];
    int head;
    int size;
    // When the queue last stopped being empty or full.  Read and written under queue_lock.
    int64_t nonempty_ns;
    int64_t nonfull_ns;

    pthread_mutex_t gen_lock;
    pthread_cond_t gen_cond;
    pthread_cond_t all_in;
    int gen;
    int arrived;
    int64_t gen_ns;
    int64_t all_in_ns;

    pthread_rwlock_t rwlock;
    int readers;
    int writer;
    int64_t a;
    int64_t b;

    WorkerStats worker[kWorkers];
};

struct Totals {
    int64_t ops;
    int64_t timed;
    int64_t tries;
    int64_t waited;
    int64_t waits;
    int lost;
    int timeouts;
    int hangs;
    int errors;
    int64_t elapsed_ns;
};

int64_t NowNs() {
    timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

// xorshift64.  It is enough for the random choices, and a seed gives the same choices again.
uint64_t NextRandom(uint64_t* state) {
    uint64_t x = *state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    return *state = x;
}

// The splitmix64 finalizer.  It gives each worker of each phase its own start state, never 0.
uint64_t MixSeed(uint64_t seed, uint64_t salt) {
    uint64_t x = seed + salt * 0x9e3779b97f4a7c15ULL;
    x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
    x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
    x ^= x >> 31;
    return x != 0 ? x : 1;
}

timespec Deadline(clockid_t clock) {
    timespec ts;
    clock_gettime(clock, &ts);
    ts.tv_sec += kTimeoutS;
    return ts;
}

void SpinBriefly(uint64_t* random_state) {
    for (int i = NextRandom(random_state) % 64; i > 0; i--) __asm__ volatile("" ::: "memory");
}

// Called with a lock held: sometimes keep it for kHoldUs.
void HoldSometimes(uint64_t* random_state) {
    if (NextRandom(random_state) % kHoldOneIn != 0) return;
    timespec ts = {0, kHoldUs * 1000};
    nanosleep(&ts, nullptr);
}

// The checks read and write the guarded words with relaxed atomics, so a lock that lets two
// owners in shows up as a wrong value, not as undefined behavior.  A load and a store, not an
// atomic increment, so that an update can be lost.
template <typename T>
T Load(const T* p) {
    return __atomic_load_n(p, __ATOMIC_RELAXED);
}

template <typename T>
void Store(T* p, T v) {
    __atomic_store_n(p, v, __ATOMIC_RELAXED);
}

// Counts a broken rule.  rc is the error of a call, or 0 for a check of the guarded words.
void Fail(WorkerStats* st, const char* what, int rc) {
    st->errors++;
    if (st->error[0] != '\0') return;
    if (rc != 0) {
        snprintf(st->error, sizeof(st->error), "%s: %s", what, strerror(rc));
    } else {
        snprintf(st->error, sizeof(st->error), "%s", what);
    }
}

// Retries a trylock until it gives something other than EBUSY, for at most the timeout.
template <typename F>
int TryLoop(F trylock) {
    int64_t end = NowNs() + kTimeoutNs;
    for (;;) {
        int rc = trylock();
        if (rc != EBUSY) return rc;
        if (NowNs() > end) return ETIMEDOUT;
        sched_yield();
    }
}

// Sorts out a timed call that timed out.  take() tries to take the lock; when it gets it,
// the lock was free and the wakeup was lost.  Returns true when the caller holds the lock.
template <typename F>
bool TimedOut(int64_t start, How how, F take, WorkerStats* st) {
    if (how != kTry && NowNs() - start > kTimeoutNs + kHangSlackNs) st->hangs++;
    if (how != kTry && take() == 0) {
        st->lost++;
        return true;
    }
    st->timeouts++;
    return false;
}

bool LockMutex(pthread_mutex_t* m, How how, WorkerStats* st) {
    int64_t start = NowNs();
    int rc;
    timespec ts;
    switch (how) {
        case kPlain:
            rc = pthread_mutex_lock(m);
            break;
        case kMonotonic:
            ts = Deadline(CLOCK_MONOTONIC);
            rc = pthread_mutex_clocklock(m, CLOCK_MONOTONIC, &ts);
            st->timed++;
            break;
        case kRealtime:
            ts = Deadline(CLOCK_REALTIME);
            rc = pthread_mutex_timedlock(m, &ts);
            st->timed++;
            break;
        default:
            rc = TryLoop([m] { return pthread_mutex_trylock(m); });
            st->tries++;
            break;
    }
    if (rc == 0) {
        if (NowNs() - start > kWaitedNs) st->waited++;
        return true;
    }
    if (rc == ETIMEDOUT) {
        return TimedOut(start, how, [m] { return pthread_mutex_trylock(m); }, st);
    }
    Fail(st, "pthread_mutex_lock", rc);
    return false;
}

bool LockRwlock(pthread_rwlock_t* rw, bool write, How how, WorkerStats* st) {
    int64_t start = NowNs();
    int rc;
    timespec ts;
    switch (how) {
        case kPlain:
            rc = write ? pthread_rwlock_wrlock(rw) : pthread_rwlock_rdlock(rw);
            break;
        case kMonotonic:
            ts = Deadline(CLOCK_MONOTONIC);
            rc = write ? pthread_rwlock_clockwrlock(rw, CLOCK_MONOTONIC, &ts)
                       : pthread_rwlock_clockrdlock(rw, CLOCK_MONOTONIC, &ts);
            st->timed++;
            break;
        case kRealtime:
            ts = Deadline(CLOCK_REALTIME);
            rc = write ? pthread_rwlock_timedwrlock(rw, &ts)
                       : pthread_rwlock_timedrdlock(rw, &ts);
            st->timed++;
            break;
        default:
            rc = TryLoop([rw, write] {
                return write ? pthread_rwlock_trywrlock(rw) : pthread_rwlock_tryrdlock(rw);
            });
            st->tries++;
            break;
    }
    if (rc == 0) {
        if (NowNs() - start > kWaitedNs) st->waited++;
        return true;
    }
    if (rc == ETIMEDOUT) {
        return TimedOut(start, how, [rw, write] {
            return write ? pthread_rwlock_trywrlock(rw) : pthread_rwlock_tryrdlock(rw);
        }, st);
    }
    Fail(st, write ? "pthread_rwlock_wrlock" : "pthread_rwlock_rdlock", rc);
    return false;
}

// Waits on c with m held until ready() is true.  *since_ns is the time when ready() last
// became true; it is read under m.  A trylock loop is not a way to wait, so kTry is a plain
// wait here.  Returns false when the caller must stop.
template <typename F>
bool WaitFor(pthread_cond_t* c, pthread_mutex_t* m, clockid_t cond_clock, How how, F ready,
             const int64_t* since_ns, WorkerStats* st) {
    while (!ready()) {
        int64_t start = NowNs();
        int rc;
        timespec ts;
        switch (how) {
            case kMonotonic:
                ts = Deadline(CLOCK_MONOTONIC);
                rc = pthread_cond_clockwait(c, m, CLOCK_MONOTONIC, &ts);
                st->timed++;
                break;
            case kRealtime:
                ts = Deadline(cond_clock);
                rc = pthread_cond_timedwait(c, m, &ts);
                st->timed++;
                break;
            default:
                rc = pthread_cond_wait(c, m);
                break;
        }
        st->waits++;
        if (rc == 0) continue;
        if (rc != ETIMEDOUT) {
            Fail(st, "pthread_cond_wait", rc);
            return false;
        }
        int64_t end = NowNs();
        if (end - start > kTimeoutNs + kHangSlackNs) st->hangs++;
        if (ready() && *since_ns < end - kLateNs) {
            st->lost++;
        } else {
            st->timeouts++;
        }
        return ready();
    }
    return true;
}

How PickHow(uint64_t* random_state) {
    return static_cast<How>(NextRandom(random_state) % kHows);
}

void MutexWorker(Shared* s, int k, uint64_t* random_state) {
    WorkerStats* st = &s->worker[k];
    for (int i = 0; i < kLockOps; i++) {
        int kind = NextRandom(random_state) % kMutexKinds;
        pthread_mutex_t* m = &s->mutex[kind];
        if (!LockMutex(m, PickHow(random_state), st)) {
            st->aborted = true;
            return;
        }
        if (Load(&s->owner[kind]) != 0) Fail(st, kTwoOwners[kind], 0);
        Store(&s->owner[kind], k + 1);
        if (kind == 1) {
            int rc = pthread_mutex_lock(m);
            if (rc != 0) Fail(st, "recursive pthread_mutex_lock", rc);
            if (rc == 0 && (rc = pthread_mutex_unlock(m)) != 0) {
                Fail(st, "recursive pthread_mutex_unlock", rc);
            }
        } else if (kind == 2 && NextRandom(random_state) % 8 == 0) {
            int rc = pthread_mutex_lock(m);
            if (rc != EDEADLK) Fail(st, "errorcheck relock did not give EDEADLK", rc);
        }
        int64_t count = Load(&s->count[kind]);
        SpinBriefly(random_state);
        HoldSometimes(random_state);
        Store(&s->count[kind], count + 1);
        st->per_mutex[kind]++;
        if (Load(&s->owner[kind]) != k + 1) Fail(st, kTwoOwners[kind], 0);
        Store(&s->owner[kind], 0);
        int rc = pthread_mutex_unlock(m);
        if (rc != 0) {
            Fail(st, "pthread_mutex_unlock", rc);
            st->aborted = true;
            return;
        }
        st->ops++;
    }
}

void Signal(pthread_cond_t* c, pthread_mutex_t* m, bool before_unlock) {
    if (before_unlock) pthread_cond_signal(c);
    pthread_mutex_unlock(m);
    if (!before_unlock) pthread_cond_signal(c);
}

void CondWorker(Shared* s, int k, clockid_t cond_clock, uint64_t* random_state) {
    WorkerStats* st = &s->worker[k];
    bool producer = k < kProducers;
    for (int i = 0; i < kItems; i++) {
        How how = PickHow(random_state);
        if (!LockMutex(&s->queue_lock, kPlain, st)) {
            st->aborted = true;
            return;
        }
        if (producer) {
            if (!WaitFor(&s->not_full, &s->queue_lock, cond_clock, how,
                         [s] { return s->size < kQueueSize; }, &s->nonfull_ns, st)) {
                pthread_mutex_unlock(&s->queue_lock);
                st->aborted = true;
                return;
            }
            s->queue[(s->head + s->size) % kQueueSize] = k * 1000000 + i + 1;
            if (s->size++ == 0) s->nonempty_ns = NowNs();
            Signal(&s->not_empty, &s->queue_lock, NextRandom(random_state) % 2 == 0);
        } else {
            if (!WaitFor(&s->not_empty, &s->queue_lock, cond_clock, how,
                         [s] { return s->size > 0; }, &s->nonempty_ns, st)) {
                pthread_mutex_unlock(&s->queue_lock);
                st->aborted = true;
                return;
            }
            st->item_sum += s->queue[s->head];
            s->head = (s->head + 1) % kQueueSize;
            if (s->size-- == kQueueSize) s->nonfull_ns = NowNs();
            Signal(&s->not_full, &s->queue_lock, NextRandom(random_state) % 2 == 0);
        }
        st->ops++;
    }
}

void BroadcastWorker(Shared* s, int k, clockid_t cond_clock, uint64_t* random_state) {
    WorkerStats* st = &s->worker[k];
    for (int r = 0; r < kBroadcastRounds; r++) {
        if (!LockMutex(&s->gen_lock, kPlain, st)) {
            st->aborted = true;
            return;
        }
        if (++s->arrived == kWorkers * (r + 1)) {
            s->all_in_ns = NowNs();
            pthread_cond_signal(&s->all_in);
        }
        bool ok = WaitFor(&s->gen_cond, &s->gen_lock, cond_clock, PickHow(random_state),
                          [s, r] { return s->gen > r; }, &s->gen_ns, st);
        st->wake_ns[r] = NowNs() - s->gen_ns;
        pthread_mutex_unlock(&s->gen_lock);
        if (!ok) {
            st->aborted = true;
            return;
        }
        st->ops++;
    }
}

// The parent's part of the broadcast phase.  It returns false when the workers did not all
// come to a round.
bool Broadcaster(Shared* s, clockid_t cond_clock, uint64_t random_state, WorkerStats* st) {
    for (int r = 0; r < kBroadcastRounds; r++) {
        pthread_mutex_lock(&s->gen_lock);
        if (!WaitFor(&s->all_in, &s->gen_lock, cond_clock, kMonotonic,
                     [s, r] { return s->arrived == kWorkers * (r + 1); }, &s->all_in_ns, st)) {
            pthread_mutex_unlock(&s->gen_lock);
            return false;
        }
        s->gen = r + 1;
        s->gen_ns = NowNs();
        bool before_unlock = NextRandom(&random_state) % 2 == 0;
        if (before_unlock) pthread_cond_broadcast(&s->gen_cond);
        pthread_mutex_unlock(&s->gen_lock);
        if (!before_unlock) pthread_cond_broadcast(&s->gen_cond);
    }
    return true;
}

void RwlockWorker(Shared* s, int k, uint64_t* random_state) {
    WorkerStats* st = &s->worker[k];
    for (int i = 0; i < kRwlockOps; i++) {
        bool write = NextRandom(random_state) % 4 == 0;
        if (!LockRwlock(&s->rwlock, write, PickHow(random_state), st)) {
            st->aborted = true;
            return;
        }
        if (write) {
            if (Load(&s->writer) != 0 || Load(&s->readers) != 0) {
                Fail(st, "the write lock has another owner", 0);
            }
            Store(&s->writer, 1);
            Store(&s->a, Load(&s->a) + 1);
            SpinBriefly(random_state);
            HoldSometimes(random_state);
            Store(&s->b, Load(&s->b) + 1);
            Store(&s->writer, 0);
            st->per_mutex[0]++;
        } else {
            __atomic_add_fetch(&s->readers, 1, __ATOMIC_RELAXED);
            if (Load(&s->writer) != 0) Fail(st, "the read lock has a writer", 0);
            int64_t b = Load(&s->b);
            SpinBriefly(random_state);
            HoldSometimes(random_state);
            if (Load(&s->a) != b) Fail(st, "a reader saw half of a change", 0);
            __atomic_sub_fetch(&s->readers, 1, __ATOMIC_RELAXED);
        }
        int rc = pthread_rwlock_unlock(&s->rwlock);
        if (rc != 0) {
            Fail(st, "pthread_rwlock_unlock", rc);
            st->aborted = true;
            return;
        }
        st->ops++;
    }
}

struct WorkerArgs {
    Shared* s;
    Phase phase;
    int k;
    clockid_t cond_clock;
    uint64_t seed;
    int done_fd;
    int go_fd;
};

void* Worker(void* arg) {
    const WorkerArgs* w = static_cast<const WorkerArgs*>(arg);
    uint64_t random_state = w->seed;
    // Wait for the start byte, so that the six workers begin at the same time.
    char c;
    if (read(w->go_fd, &c, 1) != 1) {
        w->s->worker[w->k].aborted = true;
    } else if (w->phase == kMutex) {
        MutexWorker(w->s, w->k, &random_state);
    } else if (w->phase == kCond) {
        CondWorker(w->s, w->k, w->cond_clock, &random_state);
    } else if (w->phase == kBroadcast) {
        BroadcastWorker(w->s, w->k, w->cond_clock, &random_state);
    } else {
        RwlockWorker(w->s, w->k, &random_state);
    }
    if (write(w->done_fd, "", 1) != 1) w->s->worker[w->k].aborted = true;
    return nullptr;
}

void Check(int rc, const char* what) {
    if (rc != 0) errx(1, "%s: %s", what, strerror(rc));
}

void InitObjects(Shared* s, bool shared, int iteration, clockid_t cond_clock) {
    int pshared = shared ? PTHREAD_PROCESS_SHARED : PTHREAD_PROCESS_PRIVATE;
    constexpr int kTypes[kMutexKinds] = {PTHREAD_MUTEX_NORMAL, PTHREAD_MUTEX_RECURSIVE,
                                         PTHREAD_MUTEX_ERRORCHECK, PTHREAD_MUTEX_NORMAL};
    for (int kind = 0; kind < kMutexKinds; kind++) {
        pthread_mutexattr_t ma;
        Check(pthread_mutexattr_init(&ma), "pthread_mutexattr_init");
        Check(pthread_mutexattr_setpshared(&ma, pshared), "pthread_mutexattr_setpshared");
        Check(pthread_mutexattr_settype(&ma, kTypes[kind]), "pthread_mutexattr_settype");
        if (kind == 3) {
            Check(pthread_mutexattr_setprotocol(&ma, PTHREAD_PRIO_INHERIT),
                  "pthread_mutexattr_setprotocol");
        }
        Check(pthread_mutex_init(&s->mutex[kind], &ma), "pthread_mutex_init");
        pthread_mutexattr_destroy(&ma);
    }
    pthread_mutexattr_t ma;
    Check(pthread_mutexattr_init(&ma), "pthread_mutexattr_init");
    Check(pthread_mutexattr_setpshared(&ma, pshared), "pthread_mutexattr_setpshared");
    Check(pthread_mutex_init(&s->queue_lock, &ma), "pthread_mutex_init");
    Check(pthread_mutex_init(&s->gen_lock, &ma), "pthread_mutex_init");
    pthread_mutexattr_destroy(&ma);

    pthread_condattr_t ca;
    Check(pthread_condattr_init(&ca), "pthread_condattr_init");
    Check(pthread_condattr_setpshared(&ca, pshared), "pthread_condattr_setpshared");
    Check(pthread_condattr_setclock(&ca, cond_clock), "pthread_condattr_setclock");
    for (pthread_cond_t* c : {&s->not_empty, &s->not_full, &s->gen_cond, &s->all_in}) {
        Check(pthread_cond_init(c, &ca), "pthread_cond_init");
    }
    pthread_condattr_destroy(&ca);

    pthread_rwlockattr_t ra;
    Check(pthread_rwlockattr_init(&ra), "pthread_rwlockattr_init");
    Check(pthread_rwlockattr_setpshared(&ra, pshared), "pthread_rwlockattr_setpshared");
    Check(pthread_rwlockattr_setkind_np(&ra, iteration % 2 == 0
                                                 ? PTHREAD_RWLOCK_PREFER_READER_NP
                                                 : PTHREAD_RWLOCK_PREFER_WRITER_NONRECURSIVE_NP),
          "pthread_rwlockattr_setkind_np");
    Check(pthread_rwlock_init(&s->rwlock, &ra), "pthread_rwlock_init");
    pthread_rwlockattr_destroy(&ra);
}

void DestroyObjects(Shared* s) {
    for (pthread_mutex_t& m : s->mutex) Check(pthread_mutex_destroy(&m), "pthread_mutex_destroy");
    Check(pthread_mutex_destroy(&s->queue_lock), "pthread_mutex_destroy");
    Check(pthread_mutex_destroy(&s->gen_lock), "pthread_mutex_destroy");
    for (pthread_cond_t* c : {&s->not_empty, &s->not_full, &s->gen_cond, &s->all_in}) {
        Check(pthread_cond_destroy(c), "pthread_cond_destroy");
    }
    Check(pthread_rwlock_destroy(&s->rwlock), "pthread_rwlock_destroy");
}

// Reads n bytes from fd.  Returns false when they do not come in timeout_ms, or at the end of
// the file.
bool ReadBytes(int fd, int n, int timeout_ms) {
    int64_t deadline = NowNs() + timeout_ms * 1000000LL;
    char buf[kWorkers];
    while (n > 0) {
        int64_t left = deadline - NowNs();
        if (left <= 0) return false;
        pollfd pfd = {fd, POLLIN, 0};
        int rc = poll(&pfd, 1, static_cast<int>(left / 1000000) + 1);
        if (rc == -1 && errno == EINTR) continue;
        if (rc <= 0) return false;
        ssize_t got = read(fd, buf, std::min(n, kWorkers));
        if (got <= 0) return false;
        n -= got;
    }
    return true;
}

// Checks what the workers of a phase left, and returns the first problem.
std::string CheckPhase(const Shared* s, Phase phase) {
    for (int k = 0; k < kWorkers; k++) {
        const WorkerStats* st = &s->worker[k];
        if (st->error[0] != '\0') return "worker " + std::to_string(k) + ": " + st->error;
        if (st->aborted) {
            return "worker " + std::to_string(k) + " stopped after " + std::to_string(st->ops) +
                   " operations";
        }
    }
    switch (phase) {
        case kMutex:
            for (int kind = 0; kind < kMutexKinds; kind++) {
                int64_t expected = 0;
                for (const WorkerStats& st : s->worker) expected += st.per_mutex[kind];
                if (s->count[kind] != expected) {
                    return std::string(kMutexName[kind]) + " mutex counted " +
                           std::to_string(s->count[kind]) + " of " + std::to_string(expected);
                }
            }
            break;
        case kCond: {
            int64_t expected = 0, got = 0;
            for (int k = 0; k < kProducers; k++) {
                for (int i = 0; i < kItems; i++) expected += k * 1000000 + i + 1;
            }
            for (const WorkerStats& st : s->worker) got += st.item_sum;
            if (got != expected || s->size != 0) return "the consumers lost items";
            break;
        }
        case kRwlock: {
            int64_t writes = 0;
            for (const WorkerStats& st : s->worker) writes += st.per_mutex[0];
            if (s->a != writes || s->b != writes) return "the writers lost a change";
            break;
        }
        default:
            break;
    }
    return "";
}

// Runs one phase with six threads or six processes.  Returns the first problem.
std::string RunPhase(Shared* s, Phase phase, bool processes, int iteration, uint64_t seed,
                     Totals* t, std::vector<int64_t>* wake_ns) {
    clockid_t cond_clock = iteration % 2 == 0 ? CLOCK_REALTIME : CLOCK_MONOTONIC;
    memset(static_cast<void*>(s), 0, sizeof(*s));
    InitObjects(s, processes, iteration, cond_clock);

    int done[2], go[2];
    if (pipe(done) == -1 || pipe(go) == -1) err(1, "pipe");
    WorkerArgs args[kWorkers];
    pthread_t threads[kWorkers];
    pid_t pids[kWorkers];
    alarm(kAlarmS);
    uint64_t salt = (static_cast<uint64_t>(iteration) * kPhases + phase) * 2 + processes;
    for (int k = 0; k < kWorkers; k++) {
        args[k] = {s, phase, k, cond_clock, MixSeed(seed, salt * (kWorkers + 1) + k), done[1],
                   go[0]};
        if (processes) {
            if ((pids[k] = fork()) == -1) err(1, "fork");
            if (pids[k] == 0) {
                close(done[0]);
                close(go[1]);
                alarm(kAlarmS);
                Worker(&args[k]);
                _exit(0);
            }
        } else {
            Check(pthread_create(&threads[k], nullptr, Worker, &args[k]), "pthread_create");
        }
    }
    if (processes) {
        close(done[1]);
        close(go[0]);
    }
    char gate[kWorkers] = {};
    int64_t start = NowNs();
    if (write(go[1], gate, sizeof(gate)) != sizeof(gate)) err(1, "write");
    close(go[1]);

    std::string failure;
    WorkerStats parent = {};
    if (phase == kBroadcast &&
        !Broadcaster(s, cond_clock, MixSeed(seed, salt * (kWorkers + 1) + kWorkers), &parent)) {
        failure = "the workers did not all come to a broadcast";
    }
    // When the processes end early, the read sees the end of the pipe.
    bool finished = ReadBytes(done[0], kWorkers, kPhaseTimeoutMs);
    t->elapsed_ns += NowNs() - start;
    if (processes) {
        for (int k = 0; k < kWorkers; k++) {
            if (!finished) kill(pids[k], SIGKILL);
        }
        for (int k = 0; k < kWorkers; k++) {
            int status;
            if (waitpid(pids[k], &status, 0) == -1) err(1, "waitpid");
            bool killed = WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL && !finished;
            if (!killed && (!WIFEXITED(status) || WEXITSTATUS(status) != 0) &&
                failure.empty()) {
                failure = "worker " + std::to_string(k) + " failed";
            }
        }
    }
    if (!finished && failure.empty()) {
        parent.hangs++;
        failure = "the workers did not finish in " + std::to_string(kPhaseTimeoutMs / 1000) + "s";
    }
    if (!finished && !processes) {
        // The threads cannot be stopped.  Print the counters and stop the test.
        for (int k = 0; k < kWorkers; k++) {
            fprintf(stderr, "worker %d: %d operations, %d lost, %d timeouts\n", k,
                    s->worker[k].ops, s->worker[k].lost, s->worker[k].timeouts);
        }
        errx(1, "FAIL: %s, threads, iteration %d: %s", kPhaseName[phase], iteration,
             failure.c_str());
    }
    if (!processes) {
        for (pthread_t thread : threads) Check(pthread_join(thread, nullptr), "pthread_join");
        close(done[1]);
        close(go[0]);
    }
    alarm(0);
    close(done[0]);

    if (failure.empty()) failure = CheckPhase(s, phase);
    auto add = [t](const WorkerStats& w) {
        t->ops += w.ops;
        t->timed += w.timed;
        t->tries += w.tries;
        t->waited += w.waited;
        t->waits += w.waits;
        t->lost += w.lost;
        t->timeouts += w.timeouts;
        t->hangs += w.hangs;
        t->errors += w.errors;
    };
    for (const WorkerStats& st : s->worker) add(st);
    add(parent);
    if (phase == kBroadcast && finished) {
        for (const WorkerStats& st : s->worker) {
            wake_ns->insert(wake_ns->end(), st.wake_ns, st.wake_ns + st.ops);
        }
    }
    if (finished) DestroyObjects(s);
    return failure;
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

}  // namespace

int main(int argc, char** argv) {
    int rounds = argc > 1 ? atoi(argv[1]) : kDefaultRounds;
    if (rounds < 1 || rounds > kMaxRounds) errx(1, "iterations must be 1 to %d", kMaxRounds);
    uint64_t seed = argc > 2 ? strtoull(argv[2], nullptr, 0) : static_cast<uint64_t>(NowNs());
    if (seed == 0) seed = 1;

    void* shared = mmap(nullptr, sizeof(Shared), PROT_READ | PROT_WRITE,
                        MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (shared == MAP_FAILED) err(1, "mmap");
    Shared* s = static_cast<Shared*>(shared);
    printf("%d iterations, %d workers, seed %#llx\n", rounds, kWorkers,
           static_cast<unsigned long long>(seed));
    fflush(stdout);

    Totals totals[kPhases][2] = {};
    std::vector<int64_t> wake_ns[2];
    std::string failure;
    for (int i = 0; i < rounds && failure.empty(); i++) {
        for (int phase = 0; phase < kPhases && failure.empty(); phase++) {
            for (int processes = 0; processes < 2 && failure.empty(); processes++) {
                std::string why = RunPhase(s, static_cast<Phase>(phase), processes, i, seed,
                                           &totals[phase][processes], &wake_ns[processes]);
                if (!why.empty()) {
                    failure = std::string(kPhaseName[phase]) +
                              (processes ? ", processes" : ", threads") + ", iteration " +
                              std::to_string(i) + ": " + why;
                }
            }
        }
    }

    int lost = 0, hangs = 0, timeouts = 0, errors = 0;
    std::string idle;
    for (int phase = 0; phase < kPhases; phase++) {
        for (int processes = 0; processes < 2; processes++) {
            const Totals* t = &totals[phase][processes];
            printf("%s, %s: %lld operations, %lld timed, %lld trylock loops, %lld locks waited, "
                   "%lld condition waits, %d lost, %d timeouts, %d hangs, %d errors, %lld ms\n",
                   kPhaseName[phase], processes ? "processes" : "threads",
                   static_cast<long long>(t->ops), static_cast<long long>(t->timed),
                   static_cast<long long>(t->tries), static_cast<long long>(t->waited),
                   static_cast<long long>(t->waits), t->lost, t->timeouts, t->hangs, t->errors,
                   static_cast<long long>(t->elapsed_ns / 1000000));
            lost += t->lost;
            hangs += t->hangs;
            timeouts += t->timeouts;
            errors += t->errors;
            // A phase in which no worker had to wait did not test the wake path.
            bool lock_phase = phase == kMutex || phase == kRwlock;
            if (failure.empty() && idle.empty() && (lock_phase ? t->waited : t->waits) == 0) {
                idle = std::string(kPhaseName[phase]) + (processes ? ", processes" : ", threads");
            }
        }
    }
    PrintLatency("broadcast wake latency, threads", &wake_ns[0]);
    PrintLatency("broadcast wake latency, processes", &wake_ns[1]);
    printf("lost wakeups: %d, hangs: %d\n", lost, hangs);

    if (!failure.empty()) errx(1, "FAIL: %s", failure.c_str());
    if (lost != 0 || hangs != 0) errx(1, "FAIL: %d lost wakeups, %d hangs", lost, hangs);
    if (timeouts != 0 || errors != 0) {
        errx(1, "FAIL: %d timeouts, %d errors", timeouts, errors);
    }
    if (!idle.empty()) errx(1, "FAIL: no worker had to wait in the %s phase", idle.c_str());
    printf("PASS\n");
    return 0;
}
