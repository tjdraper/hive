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

**Done when:** both binaries print plausible samples in Docker containers of Debian, Ubuntu, Alpine and Rocky, on x86_64 and aarch64; in the test VM, with a pinned TLS connection to the development Hive held open, Scout stays within §3's CPU and memory budget; and the tests pass. If it doesn't fit, record the measurements here and stop for a decision.
