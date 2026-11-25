# Server Metrics — Plan

This folder is the plan for server metrics: a small program on each server, called Scout, that reads CPU, memory, swap, disk, network, process and container figures and sends them to Hive, and pages in Beekeeper to see them. Start every session by reading this file and the slice's file. §12 describes the parts of Hive this builds on, and Part 2 how the work is done.

---

## Checklist

Check off a slice here when its "done when" is true.

### Phase A — Scout

- [x] [A1. Scout and what it reads](01-A1-ScoutAndWhatItReads.md) — Engine, 2 sessions
- [x] [A2. Enrolling a Scout](02-A2-EnrollingAScout.md) — Engine, 1–2 sessions
- [x] [A3. Sending and storing samples](03-A3-SendingAndStoringSamples.md) — Engine, 2 sessions
- [x] [A4. Installing on Linux](04-A4-InstallingOnLinux.md) — Engine, 1–2 sessions, needs you
- [x] [A5. Signed Scout releases](05-A5-SignedScoutReleases.md) — Engine, 1–2 sessions, needs you

### Phase B — Metrics in Beekeeper

- [x] [B1. Servers without SSH details](06-B1-ServersWithoutSSHDetails.md) — Mixed, 1–2 sessions
- [x] [B2. Adding metrics to a server](07-B2-AddingMetricsToAServer.md) — Mixed, 1 session, installed build
- [x] [B3. Installing Scout from Beekeeper](08-B3-InstallingScoutFromBeekeeper.md) — Mixed, 1–2 sessions, needs you
- [x] [B4. Reading metrics from Hive](09-B4-ReadingMetricsFromHive.md) — Engine, 1 session
- [x] [B5. The dashboard](10-B5-TheDashboard.md) — UI, 1–2 sessions
- [x] [B6. A server's metrics](11-B6-AServersMetrics.md) — UI, 2 sessions
- [x] [B7. Containers and services in Scout and Hive](12-B7-ContainersAndServicesInScoutAndHive.md) — Engine, 1–2 sessions
- [ ] [B8. Containers and services in Beekeeper](13-B8-ContainersAndServicesInBeekeeper.md) — UI, 1 session
- [ ] [B9. Metrics on iPhone and iPad](14-B9-MetricsOnIPhoneAndIPad.md) — UI, 1 session, TestFlight

### Phase C — Alerts, Macs and release

- [ ] [C1. Metric alerts](15-C1-MetricAlerts.md) — Mixed, 1–2 sessions
- [ ] [C2. The Hive Mac's metrics](16-C2-TheHiveMacsMetrics.md) — Mixed, 1–2 sessions, installed build
- [ ] [C3. Scout on other Macs](17-C3-ScoutOnOtherMacs.md) — Engine, 1–2 sessions, installed build, needs you
- [ ] [C4. README and release](18-C4-READMEAndRelease.md) — Mixed, 1 session, needs you

---

## Milestones

| Milestone | What you can do | Slices |
| --- | --- | --- |
| M1. Scout reports | Install Scout on a Linux server with one command, have it send samples to Hive over the tailnet, and update it with a signed release | A1–A5 |
| M2. Metrics in Beekeeper | Add metrics to any server, installed from Beekeeper where Hive can, and see every server on a dashboard and each server's history, processes and containers on its own page, on every platform | B1–B9 |
| M3. Watched | Email when a server stops reporting or runs short of disk, memory or CPU; the Hive Mac's own metrics, and Scout on other Macs; published | C1–C4 |

---

# Part 1 — What we're building

## §1. Scout

- **Scout is one program, `hive-scout`,** that runs on each server as a service, reads the figures in §4 every 10 seconds, and sends them to one Hive. It's named for the bees that fly out and report back.
- **Scout only sends.** It never listens on a port, and never runs, reads or changes anything because Hive asked over its connection. Hive's answers to it carry only acknowledgements and refusals. A Hive taken over by someone else can't use Scout to reach into a server. Installing and updating go over SSH instead, under their own rules (§2).
- **It's written in Swift,** in a package of its own (`Scout/`), and built for Linux with Swift's Static Linux SDK: a fully static binary on musl, one for x86_64 and one for aarch64, that runs on any distribution with nothing to install alongside it. One language for the whole project, and Scout shares its wire types with Hive. A1 measures it, with its TLS and crypto linked in, against the budget in §3 first. If Swift can't meet the CPU budget, stop and decide before going further; Go is the fallback. Memory is a goal, not a reason to leave Swift (§3).
- **Linux first,** since your servers run it. macOS comes in Phase C, with the same program and its own readers.
- **The Hive Mac reports itself,** with nothing to install (C2). It's usually doing a server's work too. Hive reads it with Scout's macOS readers and writes straight to its metrics, with no enrollment or connection, and it shows on the dashboard beside the servers. The daemon runs as your user and never takes back root for this, so C2 finds out which other users' processes it can see.
- **Scout runs unprivileged,** as a `hive-scout` system user. Installing and updating it need root (§2). Linux lets any user read every process's CPU and memory figures in `/proc`, unless `/proc` is mounted with `hidepid`. Scout still installs there, reports that processes are hidden, and sends everything else.
- **It's installed as a service:** systemd on almost every distribution, OpenRC on Alpine (A4). Other init systems can run `hive-scout run` themselves.
- **Scout has its own version,** raised only when Scout changes, so a Hive release that leaves Scout alone doesn't ask you to update every server. Its **protocol version** is separate again, raised only when what Scout sends changes.

## §2. How Scout reaches Hive

- **Scout sends to Hive, rather than Hive pulling over SSH.** A server can have metrics without backups or an SSH key on it; Scout keeps samples while Hive is unreachable, so the Mac sleeping or restarting leaves no gap; Hive doesn't hold a connection open to every server; and later heartbeats would need servers to reach Hive anyway.
- **Over Hive's own port and TLS** (§12). Hive has to listen on an address the server can reach, such as its Tailscale address. Nothing about Hive's network rules changes: TLS 1.3 ends at Hive, and the tailnet is treated as the open internet.
- **Scout pins Hive's key** from the enrollment code, the same hash Beekeeper pins, and refuses any other. After Regenerate Identity or a restore on a new Mac, every Scout stops sending and has to be enrolled again. It keeps its samples meanwhile (§5).
- **Each Scout has its own P-256 key,** made at enrollment and kept in a `0600` file owned by `hive-scout`. Servers have no Secure Enclave, so root on that server can read it, and with it send false figures for that server and nothing else.
- **Enrolling** (A2) works like pairing a device (§12): a paired Beekeeper opens an enrollment window for one server, with confirmation, since it gives something new access. The code it gives carries the Hive ID, the address options, the key hash and a one-time token, is single-use, and expires in 15 minutes. Several servers can have a window open at once, and none of them affects a device's pairing window. Scout sends its public key through the existing pairing endpoint, so the list of routes open without signing in stays as it is.
- **The code never goes on a command line.** Scout reads it from standard input, so it doesn't show in `ps`, in `sudo`'s log or in the journal. A pasted command still leaves it in shell history, where it's useless once used or expired.
- **Signing in** is the same challenge and short-lived session token as a device. A Scout's session is for one server and reaches only Scout's routes. A device's session can't use them either.
- **Hive accepts the current protocol version and the one before it,** so Scouts can be updated whenever it suits you. An older one is refused with a message telling it to update, which it logs and Beekeeper shows.
- **Removing a server's metrics, or the server,** revokes its Scout's key and ends its sessions at once. Removing the server deletes its metrics history too; removing only its metrics keeps the history until it ages out (§6).
- **Hive limits what a Scout can send:** how often, how large a request, how many samples in one, how many filesystems, disks, interfaces, process groups, containers and services in a sample, how many new names a server introduces in a day, and values that are finite and in range. A server that's been taken over can fill only its own share of the store. Nothing a Scout sends ever goes into a command Hive runs.
- **Installing and updating** (A4, A5, B2, B3) never go through Scout's connection to Hive:
  - **From Beekeeper, over Hive's SSH access,** when Hive signs in as root or a user with passwordless `sudo`. Hive already controls such a server, so this adds nothing it couldn't do.
  - **A command you paste once as root,** when Hive's user has no root access. It installs Scout and a `sudo` rule (or `doas`, on Alpine without `sudo`) letting that user run only Scout's own management command as root, so Beekeeper handles updates from then on. Servers without SSH details always use a pasted command.
  - **Beekeeper builds the pasted command itself,** from the download address and hashes built into Beekeeper, the enrollment code and the SSH user's name. It checks the code and the name against strict patterns first, so a Hive taken over by someone else can't slip a command of its own into what you paste as root. Scout checks the name again before writing it into a `sudo` rule.
  - **Beekeeper checks which way applies,** and shows the command with the reason when Install can't work.
  - **The installed Scout checks every update itself** (A5): a signed statement of version, CPU type and hash, signed with Sparkle's key for a release, for a binary held in memory, never older than the one installed. It stages the new binary where only root can write and renames it into place. Through the narrow `sudo` rule, a Hive taken over by someone else can install only genuine, current Scout releases.
  - **No updating itself.** Scout runs unprivileged, and a root updater on every server would trust whatever the release publishes without you deciding.

## §3. What Scout may cost a server

Collecting must never be the reason a server is slow. The budget, measured in A1 and checked again in A4:

- **CPU:** under 0.15% of one core on average, on a server with a few hundred processes and a few dozen containers. Most of it is the kernel writing out each process's figures, which grows with the number of processes (A1).
- **Memory:** under 20 MB resident, with its buffer full and its connection open. This is a goal to keep working toward, not a limit: going over it is recorded in the slice that measured it and worked on, but never stops a slice or means leaving Swift. `MemoryMax` below is the hard limit.
- **Disk:** no writes while running, apart from the system journal when something goes wrong. Its key and settings are written at enrollment.
- **Network:** one TLS connection kept open, a few KB a sample
- **Caps the service manager enforces,** so a fault in Scout can't hurt the server either: under systemd, `CPUQuota=5%`, `MemoryMax=64M`, `Nice=10` and an idle I/O class

## §4. What Scout reads

From `/proc` and `/sys` on Linux. Each is a handful of small reads.

- **CPU:** total use, split into user, system, I/O wait and steal. Steal is the time a virtual server's host gave its CPU to someone else, the usual reason a VPS is slow while looking idle. Load averages and the number of cores, so load can be shown against capacity.
- **Memory:** total, used, available (the kernel's `MemAvailable`, not "free", which counts cache as used), and cache. Swap total and used, and pages swapped in and out per second. Swap in use is often harmless; swapping in steadily means the server is short of memory.
- **Pressure:** the kernel's pressure figures for CPU, memory and I/O (`/proc/pressure`), the share of time work was stalled waiting for each. Found by whether the files exist: they need kernel 4.20 or later and can be turned off at build or boot, as some distributions do. The clearest single sign a server is struggling.
- **Disks:** for each local filesystem, size, used, available, and inodes used and free. A disk can run out of inodes with space left, from many small files such as sessions or caches. Network and memory filesystems are left out: `statfs` on a hung network mount blocks. Read and write bytes and operations per second for each disk, and the share of time it was busy.
- **Network:** received and sent bytes per second, and errors and drops, for each real interface, including `tailscale0`. Loopback and Docker's virtual interfaces are left out.
- **Processes:** each one's CPU share since the last sample, and its memory of its own: resident memory less what it shares, so forty `php-fpm` workers sharing one cache don't count it forty times. Sent as the top 10 by CPU and the top 10 by memory, grouped by command name and user with a count, so forty workers at 2% each show as one line at 80%. The number of processes and of zombies. Grouped memory is still approximate, and labelled so; containers and services below give the exact figure.
- **Containers and services** (B7), from their cgroups under `/sys/fs/cgroup`, which any user can read:
  - **Each Docker container's** CPU, memory, I/O and process count, sent as the top 10 by CPU and by memory. Each process group in the lists says which container or service it's in, from the cgroup that lists it, and a container's users show by number, since the server's names for them are another system's.
  - **Each systemd service's** CPU, memory, I/O and process count, also as the top 10 by each. Unlike the process lists, these count work done by processes that start and finish between samples, such as cron jobs and command-line PHP.
  - **Scout never asks Docker.** Access to Docker's socket is root on the server, which Scout must never have. Hive names containers instead, with a read-only `docker ps` over SSH where its SSH user can run `docker`, as it already does to find database containers. Swarm replicas are grouped by service, and Compose ones by project and service, since every Compose project has its own `db`.
  - **Where Hive can't run `docker`,** or the server has no SSH details, containers show by short ID and the commands running in them.
- **The server itself:** uptime, so a reboot shows; the distribution from `/etc/os-release`; the kernel version; Scout's version; and whether processes are hidden by `hidepid`.

Left for later:

- **Failed systemd units, open file handles, TCP connection counts,** and other figures, once the dashboard shows what's missing.
- **Each process on its own,** rather than grouped by command and user. Scout sends only the top groups, so this needs Scout to send single processes, a new protocol version, and Hive to keep them (B6).

## §5. Timing

- **Every 10 seconds,** on the clock's 10-second marks so servers line up, each sample is sent as it's taken.
  - 10 seconds catches a spike that lasts a quarter of a minute, which a 1-minute average flattens to almost nothing. Rollups keep each period's highest value (§6), so a spike still shows in a 30-day chart.
  - 5 seconds would double the cost and the storage for a dashboard you look at, not a profiler.
  - 1 minute would be cheaper still, but a live page that changes once a minute feels broken, and short spikes vanish.
- **Fixed, not a setting,** so every server's data has the same shape. Revisit only if a reason shows up.
- **While Hive is unreachable,** Scout keeps the last hour of samples whole, and for the 23 hours before that each minute's average and highest, and the lowest where §6 keeps it, without processes, all in memory: about 3 MB, as A3 measured with the test VM's samples, and 4 MB with a few more filesystems, interfaces and process groups. It counts against §3's memory goal. Once Hive answers, the newest sample goes first, so the dashboard and alerts are current at once, then the rest oldest first. Hive files the per-minute figures straight into its 1-minute and 1-hour resolutions. Anything older than a day is dropped, and Scout restarting loses what it kept.
- **Sending twice is harmless.** A request that timed out may have landed, so Hive keeps one sample per server and time, and a repeat changes nothing.
- **Times are the server's clock.** Each request also carries Scout's clock at the moment it's sent, so Hive knows each server's offset even while a backlog arrives. Beekeeper warns when it's more than a minute. A server whose clock runs so far ahead that Hive refuses its samples shows as "clock ahead", not as stopped reporting.

## §6. How Hive keeps metrics

- **In a SQLite database of its own** (`Metrics/metrics.sqlite` in the data directory), apart from Hive's store: its writes don't contend with the store's, and losing it loses history, never configuration.
- **The `Metrics/` folder is left out of Time Machine** with the backup exclusion attribute, so the database's write-ahead log is too. Time Machine copies a changed file whole, and these change every 10 seconds. The README says to exclude it in Arq or other tools too. It isn't in recovery files, so a restore on a new Mac starts metrics afresh.
- **Three resolutions,** each holding the average and highest value for its period. The lowest is kept only where it matters, such as available memory and free disk space; for CPU, load or network traffic it's almost always zero, and would take a third of every row.

  | Resolution | Kept for | For ranges |
  | --- | --- | --- |
  | 10 seconds | 24 hours | up to a day |
  | 1 minute | 7 days | a week |
  | 1 hour | 1 year | a month and longer |

- **Processes, containers and services** are kept with every 10-second sample for 24 hours. Each hour's top 10 process groups are kept for 14 days, and its busiest container groups and systemd services, with their average and highest CPU and memory, for 90 days, to show which site grew.
- **Roughly 30–40 MB for each server,** once it's been reporting for a year, so about 350 MB for ten servers. It stays there, since older data is pruned. A3 measured 32 MB with a year of made-up data (three filesystems, two disks, two interfaces and 20 process groups a sample), a quarter of it the last day's processes. **Containers and services add about 20–25 MB** on a server running 50 containers (B7): about 15 MB for the last day's samples, measured on the test VM at 1.45 KB a sample, and 5–9 MB for 90 days of hours, so about 55–65 MB for such a server.
- **Rollups and pruning** run as samples arrive and once an hour, and a late batch from a Scout that was cut off updates the periods it falls in.

## §7. Beekeeper

Built with you in Phase B. The starting point:

- **Servers with metrics** sit under servers, where Beekeeper already lists each server's backup jobs. A server can have metrics, backup jobs or both, so one added only for metrics needs no SSH details (B1).
- **A dashboard** of every server reporting to the Hive, and the Hive Mac once C2 adds it, with a card each: whether it's reporting, CPU, memory, swap, its fullest disk, and a sparkline of the last hour. Servers with a problem come first.
- **A page for each server:** what it is (distribution, kernel, cores, memory, uptime, Scout's version), a range from an hour to a year, and charts for CPU, load, memory and swap, pressure, each disk, disk activity and the network. Choosing a moment on a chart shows the processes and containers at that moment. Backup runs are marked on the charts, so you can see when a backup loaded the server.
- **A page for each kind of figure,** reached from the server's page: processes, live and grouped (each process on its own is left for later, §4); each disk with a forecast of when it fills at its recent rate; containers and services; and so on.
- **Live while open:** the dashboard and a server's page update with every sample through live updates (§12), which carry only each server's latest figures, never a backlog.
- **iPhone and iPad** in B9.

## §8. Alerts

In C1, through Hive's existing email alerts and their repeat rules (§12):

- **A server stops reporting:** no sample for 3 minutes. When two or more servers stop at once, the cause is probably Hive's own network, so that's one email, not one for each server. Nothing counts as stopped for the first few minutes after Hive starts, the Mac wakes, or Hive's listen addresses change.
- **A disk or its inodes** over 90%, or forecast to fill within a week
- **Memory:** available under 10%, or swapping in steadily, for 10 minutes
- **CPU** over 90%, or steal over 20%, or load over twice the cores, for 15 minutes
- **A server's clock** far enough ahead that its samples are refused
- **A server restarted**
- **Limits and how long they last** are set for each server, with these as defaults

## §9. Logs and the audit log

- **The audit log** records opening an enrollment window, a Scout enrolling, installing, updating and uninstalling Scout from Beekeeper, a server's metrics being removed, and alert limits changing.
- **The job log** isn't for metrics. Samples aren't jobs.
- **Hive's system log** records counts and decisions: samples received, refused and why, rollup timings. Never a server's name or address, mount points, process, user, interface or container names, or anything else a Scout reports.
- **Scout logs to the system journal** (or the system log on a Mac): enrolling, connecting, being refused, how many samples it's holding. Never its key or the enrollment code.

## §10. Room for log collection

Scout will collect logs in a later plan. Nothing here builds that, but these keep it from needing a rewrite:

- **Scout is a server's reporter, not a metrics program.** Its wire types, routes and code name what each one carries, such as metrics samples, so logs arrive as a kind of their own on their own route.
- **Sending handles more than one kind,** each with its own buffer and limits, and metrics go first. A backlog of logs must never hold up a sample, and filling the log buffer must never cost metrics.
- **What Scout reads is set on the server,** never by Hive (§1). A Hive taken over by someone else could otherwise point Scout at any file on the server. Logs will need a setting on the server listing what to send.

Logs will also need things metrics don't: reading the journal or `/var/log` means joining groups such as `systemd-journal` or `adm`, so Scout sees more than it does now. Their volume will likely mean holding them on disk, against §3's no-writes rule. And they'll need their own budget, storage and retention. Those are decisions for that plan.

## §11. Open questions

- [x] Does a static Swift binary, with its TLS and crypto, meet §3's CPU budget, and how close does it come to the memory goal? Yes, at 0.100% with a few hundred processes, after the budget was raised from 0.1% to 0.15%, since most of the cost is the kernel's and any language pays it. Memory is 22 MB, over the goal (A1).
- [x] How Scouts update: from Beekeeper over SSH where Hive has root or A4's `sudo` rule, otherwise a pasted command, which keeps the key. Never by updating themselves (§2, A5, B3).
- [ ] What can an unprivileged process read of other users' processes on macOS? Hive's own Mac depends on it (C2), and whether Scout on other Macs runs as root (C3).
- [x] Container names without Docker's socket: Hive names them over SSH with `docker ps`, and Scout sends only IDs (§4, B7)
- [x] Does notarization accept Linux binaries in `Hive.app`'s resources? Yes, with no issues; they add about 15 MB to the downloads (A5)

## §12. What this builds on

Hive and Beekeeper as they stand. The code named here is the reference; `Plans/HighLevelPlan/` has the history behind it, for background only.

- **The daemon** is a LaunchDaemon that starts as root, records the user who installed it, and gives up root for good before touching the network, keys or secrets (`DaemonStartup/`). Its data directory is `~/Library/Application Support/Hive/`. Logic that can be tested without the daemon lives in HiveCore; HiveKit holds only the API types and the client Beekeeper uses (`Architecture/README.md`).
- **The network:** Hummingbird 2 on SwiftNIO, TLS 1.3 only, with a self-signed certificate for a P-256 identity key in the Secure Enclave. Clients pin the SHA-256 of that key's X9.63 form and ignore everything else about the certificate. Hive listens on `127.0.0.1` and the addresses chosen in its settings, on port 4483 (4484 for the development daemon). Address options, the hosts a device can reach the Hive at, are part of `HiveSettings`.
- **The request gate** (`APIServer/RequestGate.swift`) turns away every request without a session before routing, except four open routes: the health check, the sign-in challenge, sign-in, and pairing.
- **Signing in:** Hive sends a nonce, the device signs it with its Secure Enclave key, and Hive returns a session token that lasts 15 minutes, kept only in memory (`Authentication/`).
- **Pairing a device** (`Pairing/`): a paired Beekeeper opens a window through a confirmed route; Hive gives a `hive1:` code (`PairingCode`) with the Hive ID, the address options, the key pin and a single-use token. `PairingWindowStore` holds one window at a time. Refusals answer 404 and count toward a per-address lockout (`FailedAttemptLimiter`, `pairingLimiter`).
- **Confirmation** (`Confirmation/`): actions that delete backups, send a secret somewhere new or give something new access need a second Secure Enclave key in Beekeeper that asks for Touch ID, Face ID or the password. Routes read `ConfirmedRequest` and check `ConfirmationRequirement` against a `ConfirmationReason`; Beekeeper sends them with `HiveLink.confirmed`.
- **The audit log** records every change made through the API and which device made it (`AuditLog/`).
- **SSH** (`SSH/`, `SSHKeys/`, `HostKeys/`): each server has its own Ed25519 key, handed to `ssh` through a short-lived `ssh-agent` of Hive's own, never written to disk. Hive connects only with the server's confirmed host key and `StrictHostKeyChecking=yes`. Servers add Hive's key to `authorized_keys` with `restrict`.
- **Docker** (`DatabaseDumps/ContainerListReader.swift`): Hive runs `docker ps` over SSH to find database containers by their Swarm or Compose service name. When it can't, the run fails with `dockerUnavailable`.
- **Email alerts** (`Email/`, `Alerts/`): SMTP through `EmailDelivery`, with alert state in the store (`AlertStore`) so a restart never sends one twice. Failures, a missing drive, overdue jobs and changed host keys are emailed again daily until resolved; space warnings once, and again only after they've cleared. A run failing for a reason with its own alert, such as the drive, sends that alert alone.
- **Live updates** (`LiveUpdates/`, HiveKit's `LiveUpdate`): a response Hive holds open, one JSON line per change, under the same sign-in as every other request. `Broadcaster` keeps a bounded queue for each listener.
- **Recovery files** (`Recovery/`) hold the configuration and every secret, encrypted to a recovery key Hive never sees. Restoring on a new Mac gives Hive a new identity key, so every device has to pair again.
- **Releases** (`Scripts/release.sh`, `Scripts/sparkle-tools.sh`): Developer ID builds of both Mac apps, notarized, updated through Sparkle, with signing keys in the Keychain and the team ID, bundle ID prefix and feeds in the gitignored `.xcconfig`. iPhone and iPad builds go through TestFlight.
- **Beekeeper's layouts** adapt with size class: a sidebar on the Mac and iPad, and `CompactNavigation` on iPhone (`HiveList/`).
- **Development:** `Scripts/build-and-test.sh` builds and tests everything and fails on any warning; `Scripts/install-test-build.sh --mac-installed` installs a signed test build; `TestServer/` and `Scripts/test-server.sh` run a test server in Docker Compose, with database containers named and labelled as Swarm would, though Docker isn't in Swarm mode; `Scripts/test-drive.sh` mounts a test backup drive. Beekeeper's Developer window, in Debug and test builds, can drive features before their screens exist.

---

# Part 2 — How the work is done

## Slices

- **Files are numbered in the order the work happens.** A slice added later is numbered into its place, and the files after it move along, links included. The checklist groups slices by phase; the numbers give the order across phases.
- **One slice per session,** sized to leave plenty of room after reading this file, the slice's file and the code it touches, including for going back and forth to adjust things. A few slices say "2 sessions" or "1–2 sessions". Split those where a natural break shows up; some name one.
- **Each slice has a kind:**
  - **Engine:** mostly code and tests, little back-and-forth needed.
  - **UI:** built with you. Expect to spend time adjusting the look and behavior together.
  - **Mixed:** an engine part first, then a UI part.
- **Each slice has a "done when".** A slice isn't finished until that's true. Before Phase B's screens exist, checks go through Beekeeper's Developer window.
- **"Installed build"** means the slice touches the daemon's registration, a permission, an entitlement, code signing or the Secure Enclave, and is checked in a copy installed with `Scripts/install-test-build.sh --mac-installed`, never a build run from Xcode or Terminal (AGENTS.md). **"TestFlight"** means it has to be checked on a real iPhone or iPad. **"Needs you"** means steps only you can take, such as making signing keys, approving something, or allowing work on a real server.
- **Order is flexible where dependencies allow.**

## Development machines

- **The test server** (§12) for anything over SSH. Development never runs anything on a real server without asking.
- **A test Linux VM,** made by a script from A1 on: systemd, Docker in Swarm mode running a few services, and a few hundred processes. A4 adds one with Alpine and OpenRC.
- **Tests use neither.** They run against temporary folders, captured `/proc` and `/sys` files, and fakes. They never run `ssh`, start the daemon or open a listening port.
- **Scout's package builds and tests on the Mac** with the rest. Linux builds run in Docker, with the Static Linux SDK, so the Xcode toolchain on the Mac doesn't matter. They're a script of their own, `Scripts/build-scout.sh`, which also runs Scout's tests on Linux. `Scripts/build-and-test.sh` runs it only when `Scout/` changed since its last success, so Docker isn't needed for everything else.
- **A development signing key** for Scout (A5), kept in this Mac's Keychain, so development builds of Hive carry signed Scout binaries. A development Scout trusts only the development key, and a release Scout only Sparkle's signing key, which also signs the Mac apps' updates.

## Every slice ends with

- `Scripts/build-and-test.sh` passing: Hive for macOS, Beekeeper for macOS and iOS, HiveKit, HiveCore and Scout, with zero warnings, SwiftLint included, and every test passing
- The installed-build checks done, when the slice has them
- A self-check against `Architecture/README.md` and `Architecture/ReviewChecklist.md`
- The slice checked off in the checklist above, with any follow-ups added to the slice files or sections they belong in
- Anything that needs a real iPhone or iPad added to [TestFlightChecks.md](TestFlightChecks.md) in this folder, which B9 starts

## Rules for every slice

- **AGENTS.md's security rules hold in every slice,** Debug builds and temporary code included. No bypass "just for testing".
- **Every refusal Scout's sessions depend on has a test,** as AGENTS.md asks: a Scout's session on a device's route, a device's session on Scout's routes, a Scout sending for another server, a revoked Scout, a sample from the future, and each limit in §2.
- **Every change made through the API goes in the audit log.**
- **HiveKit holds Beekeeper's wire contract only,** and `ScoutProtocol` Scout's. Hive's logic goes in HiveCore.
- **Features not in Part 1** go under "Left for later" in §4 or in §11 until you decide otherwise.
