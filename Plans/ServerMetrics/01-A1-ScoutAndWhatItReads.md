# A1. Scout and what it reads

**Phase A — Scout** · Engine, 2 sessions

References like §4 point to [00-Info.md](00-Info.md).

Answers the first open question before anything depends on it: can a static Swift binary, with everything it will link, read §4 within §3's budget? A natural split: the package, the build and the TLS measurement in the first session, the readers in the second.

## The package and the build

- **The `Scout/` package:**
  - `ScoutProtocol`: the wire types Scout and Hive share, buildable on Linux and macOS. HiveCore imports it in A2. Beekeeper never does; what it reads comes through HiveKit (B4).
  - `ScoutCore`: the readers, the sample they make, and later the buffer and the client. Testable without a network or a real `/proc`.
  - `hive-scout`: the executable. In this slice, `hive-scout sample` prints one sample as JSON and `hive-scout watch` prints one every 10 seconds.
- **Keep the binary small:** `FoundationEssentials` rather than all of Foundation, since Foundation's internationalization data alone is tens of megabytes.
- **The connection, chosen and measured here,** not in A2, since it's the largest thing Scout links: SwiftNIO with NIOSSL on a single event-loop thread, and swift-crypto for P-256. `URLSession` on Linux can't pin a key. `hive-scout watch --tls <host>` makes a pinned TLS 1.3 connection to the development Hive and holds it open, so the measurement includes it.
- **`Scripts/build-scout.sh`** builds both Linux binaries in Docker with the Static Linux SDK, at a fixed Swift version, checks with `file` that they're static, and runs Scout's tests on Linux. `Scripts/build-and-test.sh` runs it only when `Scout/` changed since its last success.
- **The test VM** (Part 2): a script that makes a disposable Linux VM with systemd, Docker in Swarm mode running a few services, and a few hundred processes, and copies a development Scout binary into it.
- **SwiftLint** covers the new package.

## The readers

- **Everything in §4 but containers and services** (B7), each parsing one file's text into values, kept apart from the code that reads the file. Rates (CPU shares, bytes per second, swapping) come from the difference between two readings, so the first sample after starting has none.
- **Processes:** read each `/proc/<pid>/stat` and `statm`, keep the previous CPU times by PID and start time, so a reused PID never gives a negative share, and forget processes that are gone. Memory of its own is resident less shared (§4). Group by command name and user. A process that exits between listing and reading is skipped, not an error.
- **Filesystems:** from `/proc/self/mountinfo`, local types only, each mount point once even when bind-mounted. `statfs` on its own thread with a timeout, so a filesystem that hangs is reported and skipped.
- **Pressure** where its files exist, and nothing where they don't
- **`hidepid`:** noticed and reported, with the rest of the sample as usual

## Tests

- Each reader against `/proc` and `/sys` files captured from real distributions (Debian, Ubuntu, Alpine, Rocky), including a kernel without `/proc/pressure`, a `hidepid` mount and a process vanishing mid-read
- Rates across a counter that wrapped, a server that rebooted between readings, and a reused PID
- Grouping: forty workers of one command become one line with their total and count, without counting shared memory forty times

**Done when:** both binaries print plausible samples in Docker containers of Debian, Ubuntu, Alpine and Rocky, on x86_64 and aarch64; in the test VM, with a pinned TLS connection to the development Hive held open, Scout stays within §3's CPU budget, with its memory measured against the goal; and the tests pass. If the CPU doesn't fit, record the measurements here and stop for a decision. If memory is over 20 MB, record it here and keep going.

## Session 1: the package, the build and the connection

Done: the `Scout/` package with the server-facts reader, `hive-scout sample` and `watch`, the pinned connection, `Scripts/build-scout.sh`, `Scripts/scout-test-vm.sh`, and Scout's steps in `Scripts/build-and-test.sh`. Left for session 2: every other reader in §4, their tests, and measuring again with them in place.

What was decided along the way:

- **Swift 6.4.2 and Static Linux SDK 0.1.0,** the image pinned by digest and the SDK by checksum, after its signature checked out against swift.org's release key. The two have to move together.
- **Everything runs on one SwiftNIO event loop** (`ScoutEventLoop`), set as the task executor for all of Scout's work. Swift's default executor on Linux is libdispatch, which starts and stops worker threads between samples: that tripled the CPU used, and under `Nice=10` each new thread logged a failure to set its priority, writing to the journal. NIO's own way of taking over the global executor needs `dlsym`, which a static musl binary doesn't have. So Scout waits with the event loop's timers, never `Task.sleep`, and looks up addresses with `getaddrinfo` on a thread of its own, never NIO's resolver, which hands lookups to libdispatch.
- **Every address a name stands for is tried in turn,** with no `AI_ADDRCONFIG`, which on glibc refuses an IPv6 address on a server without one of its own.
- **`watch --tls` keeps the connection open with Hive's health check** on every sample, since Hive closes a connection that's quiet for 30 seconds. A3 replaces it with the samples themselves.
- **The test VM is an OrbStack machine:** Debian 12 on arm64, with its own systemd, users, processes and Docker in Swarm mode, on a kernel shared with OrbStack's other machines. It reaches the Mac's loopback at `host.orb.internal`. Its kernel has no `/proc/pressure`.
- **SwiftLint runs on Scout directly** in `build-and-test.sh`, since SwiftPM shows the plugin's warnings only when it reruns the plugin, which an incremental build skips.

Measured in the test VM, with 334 processes and 9 containers, Scout reading only the server facts, as its own user under §3's caps, with a pinned TLS 1.3 connection to the development Hive held open, over 5 minutes:

| | Measured | Budget |
| --- | --- | --- |
| CPU | 0.023–0.033% of one core | under 0.1% |
| Memory | 15.5 MB resident, 19.3 MB at its peak | goal: under 20 MB |
| Journal | nothing written | nothing unless something goes wrong |
| Binary | 18 MB (x86_64), 17 MB (aarch64), stripped | |

Without the connection, it used 0.017% and 9.4 MB, with a 12.8 MB peak. Memory is the tight one: the peak is under a megabyte from the 20 MB goal before the readers and A3's buffer. If session 2 goes over, record it and look first at what makes the peak 4 MB above the steady figure, then at linking without PIE, whose relocations copy the binary's data pages. The binary's size is mostly two copies of BoringSSL, NIOSSL's and swift-crypto's, and the Swift runtime. No internationalization data is linked.

## Session 2: the readers

Done: every reader in §4 but containers and services, their tests against `/proc` and `/sys` files captured from Debian 12, Ubuntu 24.04, Alpine 3.22 and Rocky 9 (and Debian 12 with `hidepid`), and the measurement below. Both binaries print plausible samples on all four distributions, on x86_64 and aarch64. `Scripts/build-and-test.sh` passes.

What was decided along the way:

- **Rates use the kernel's clock and its boot ID** (`ReadingTime`), so a wall clock set back gives no negative rate, and a server that restarted between samples gives none at all, since its counters started again.
- **Counters that go backwards give no rate** that sample, as when an interface is recreated or a disk replaced, except a disk's time busy, which the kernel keeps in 32 bits and so is taken as having wrapped.
- **Processes are grouped by command and user,** the user read from who owns the process's files. A process's CPU share counts all of its work when it started since the previous reading, which also covers a reused PID, and none of its earlier work when it's first seen late. Kernel threads are counted with no memory and no `statm` read.
- **Filesystems:** local types only, each device once at its shortest mount point. `statvfs` runs on a thread of its own with a 2-second timeout; a filesystem that times out is skipped until its call returns, and a spare thread serves the others meanwhile.
- **Disks** are the entries in `/sys/block` outside `devices/virtual`, so loop, RAM, LVM and RAID devices are left out and nothing is counted twice. **Network** leaves out loopback, `docker*`, `veth*` and Docker's `br-<12 hex>` bridges.
- **What made the CPU fit:** the first build of the readers used 0.17%. Splitting the kernel's files by byte rather than by `Character` (Swift works out grapheme boundaries for every character), keeping each process's `stat` and `statm` open between readings and reading them again with `pread` (opened again when the process's command changes, or it exits), skipping kernel threads' `statm`, and reading `/sys/block` only when the list of devices changes brought it to 0.100%.

Measured in the test VM, with 336 processes and 9 containers, every reader in place, as Scout's own user under §3's caps, with a pinned TLS 1.3 connection to Hive held open, over 5 minutes:

| | Measured | Budget |
| --- | --- | --- |
| CPU | 0.100% of one core (0.030% in Scout, 0.070% in the kernel); earlier runs of nearly the same build 0.103% and 0.120% | under 0.15% (was 0.1%) |
| Memory | 22.0 MB resident, 25.9 MB at its peak | goal: under 20 MB |
| Journal | nothing written | nothing unless something goes wrong |
| Binary | 19 MB (x86_64), 17 MB (aarch64), stripped | |

**The CPU was at the budget, not under it, so the budget was raised to 0.15%,** keeping Swift and reading processes every 10 seconds. Seven tenths of it is the kernel writing out each process's `stat` and `statm` text and listing `/proc`, which any language pays the same, so Go wouldn't change it. It grows with the number of processes: roughly 0.2–0.25% on a server with a thousand, an estimate not yet measured. What's left on Scout's side is small: reading `/proc/self/mountinfo` only when the kernel signals a mount change would save about 7% of the total, within the noise between runs, so it wasn't done.

**Memory is over the goal,** recorded and not a reason to stop (§3). Resident memory rose from 15.5 MB in session 1; of the 22.0 MB now, 14.5 MB is memory Scout allocates and 7.5 MB the binary's pages. What the readers keep hasn't been broken down yet. The peak is still about 4 MB above the steady figure, as in session 1. The open process files hold kernel memory too, which counts toward `MemoryMax` but not toward these figures.
