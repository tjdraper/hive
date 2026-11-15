# Server Metrics Plan — Summary

The plan is in `Plans/ServerMetrics/`: a main file, `00-Info.md`, and 18 slice files in three phases.

- **Phase A (A1–A5), Scout:** the program on each server, enrolling, sending and storing samples, installing on Linux, and signed releases.
- **Phase B (B1–B9), Beekeeper:** servers without SSH details, adding metrics, installing from Beekeeper, the dashboard, a server's page, containers, and iPhone and iPad.
- **Phase C (C1–C4):** alerts, the Hive Mac's own metrics, Scout on other Macs, and the release.

## Reporting interval: every 10 seconds

Each sample is sent as soon as it's taken.

- **Why not 1 minute:** a 1-minute average hides a 15-second spike, and a live page that changes once a minute feels broken.
- **Why not 5 seconds:** it doubles the cost and storage for a dashboard you look at now and then.
- **Spikes stay visible:** Hive's hourly and per-minute summaries keep the highest value in each period, so a spike still shows on a 30-day chart.

## Main decisions

- **The server program is called Scout (`hive-scout`).** It sends data to Hive, rather than Hive pulling it over SSH. That lets a server have metrics without having backups, and the server keeps up to a day of data while the Mac sleeps or Hive is down. Scout never opens a port and never acts on anything Hive sends over its connection.
- **Scout is written in Swift, built as a fully self-contained Linux binary.** One file per CPU type runs on any distribution. This is the biggest risk, so the first slice (A1) measures it, with its networking and encryption included, before anything else. The limits are under 0.1% of one CPU core, under 20 MB of memory, and no disk writes while it runs. If Swift can't meet them, Go is the fallback, and you'd decide then.
- **Security uses the same scheme as pairing a new Beekeeper device.** In Beekeeper you confirm with Touch ID and get a single-use enrollment code that expires after 15 minutes. Scout locks onto Hive's key and has its own key. A Scout's session can only send metrics for its own server, and the plan adds tests for each refusal.
- **Installing:** from Beekeeper over SSH, or a command you paste; see "Installing and updating Scout" below. Scout installs as a systemd service (OpenRC on Alpine) and runs as its own unprivileged user. The service manager caps how much CPU and memory it can use.
- **Metrics live in their own folder on the Hive Mac, excluded from Time Machine.** Time Machine copies a changed file whole, and the database changes every 10 seconds. That means metrics history is lost when you restore Hive on a new Mac. Expect roughly 30–40 MB per server, about 350 MB for ten servers, reached after a year and staying there as older data is pruned; slice A3 measures the real figure.
- **Servers without SSH details:** a server can be added by name only, with no SSH details, until it gets a backup job (B1).

## What Scout reads beyond what you listed

- CPU steal time, which shows when a virtual server's host is taking its CPU.
- The kernel's pressure figures, which show how often work stalls waiting for CPU, memory or disk, on servers whose kernel has them.
- How fast the server is swapping, which tells you more than how much swap is in use.
- Inodes, since a disk can run out of them while it still has space.
- Disk and network activity.
- Uptime, so reboots show.

Processes are grouped by command name, so forty `php-fpm` workers show as one line. Their memory leaves out what the workers share, so a shared cache isn't counted forty times, and it's labelled as approximate.

## Containers and services

Slices B7 and B8 show which site is using a server when every site runs the same `nginx` and `php-fpm`.

- **Scout reads each container's figures without Docker.** Each container's CPU, memory, I/O and process count come from its cgroup under `/sys/fs/cgroup`, which any user can read. Each process in the lists also says which container it's in.
- **Systemd services too.** Their figures include work by processes that start and finish between samples, such as cron jobs and command-line PHP, which the process lists miss.
- **Hive names the containers, not Scout.** Docker's socket gives root, which Scout must never have. Hive runs a read-only `docker ps` over SSH when a new container appears, as it already does to find database containers. Swarm replicas are grouped by service, so `buzzingpixel_db.1.<id>` shows as `buzzingpixel_db`, and Compose ones by project and service, since every Compose project has its own `db`.
- **Without `docker` access over SSH,** containers show by short ID and the commands running in them.
- **Storage:** the top 10 containers by CPU and by memory with each sample, like processes, plus each service's hourly figures for 90 days, to show which site grew.

## How long history is kept

| Data | Kept for |
| --- | --- |
| Every 10-second sample | 24 hours |
| Per-minute summaries | 7 days |
| Per-hour summaries | 1 year |
| Process and container lists with each sample | 24 hours |
| Hourly top 10 processes and containers | 14 days |
| Each container or service's hourly figures | 90 days |

Summaries keep each period's average and highest value. The lowest is kept only where it matters, such as free memory and free disk; for CPU, load or network traffic it's almost always zero.

## When Hive can't be reached

- Scout holds samples in memory while Hive is unreachable: the last hour in full, and each minute's average and highest for the 23 hours before that, about 2 MB. When Hive answers again, it sends the newest sample first so the dashboard and alerts are current, then the rest oldest first.
- It waits longer between tries, up to a minute, so a sleeping Mac doesn't keep every server busy retrying.
- Connecting and every request have timeouts, so a Hive that accepts a connection and then hangs counts as unreachable. Taking samples never waits on sending them.
- Sending a sample twice is harmless: Hive keeps one per server and time.
- If Hive refuses it (its key was revoked, or Hive's key changed), Scout logs it once, keeps sampling and tries again hourly. Enrolling it again reconnects at once, keeping what it holds.
- A server whose clock runs far ahead shows as "clock ahead", not as stopped reporting.

## Installing and updating Scout

Two ways, and Beekeeper picks the right one by checking the server over SSH first (slice B3):

- **From Beekeeper, with one button,** when Hive signs in as root or as a user with passwordless `sudo`. Hive already controls such a server, so this adds no new risk.
- **A command you paste once as root,** when Hive's SSH user can't run commands as root. Beekeeper says why, for example "Hive signs in as `deploy`, which can't run commands as root". The command installs Scout and adds a `sudo` rule (or `doas` on Alpine) letting that user run only Scout's own management command as root. From then on Beekeeper handles updates and uninstalling.
- **Servers without SSH details** (metrics only) always use the pasted command (B2).

The pasted command is built by Beekeeper itself, from the download address and hashes built into Beekeeper. It downloads the binary into a private folder and checks its SHA-256 before running it. The enrollment code and SSH user name are checked against strict patterns first, so a Hive taken over by someone else can't slip its own commands into what you paste as root. The code goes in on standard input, so it never shows in `ps` or `sudo`'s log.

Updates:

- **Scout has its own version,** raised only when Scout changes, so a Hive release that leaves Scout alone doesn't ask you to update every server.
- **Signed releases (A5):** the release script signs each binary with a Scout release key, kept in the Keychain like the Sparkle key, and puts the binaries in `Hive.app` so Hive can send them over SSH without the server reaching GitHub. Development builds use a separate development key.
- **Noticing an old Scout:** each Scout reports its version when it signs in, and Beekeeper marks one that's out of date, with Update and Update All buttons where Hive has SSH access, or the update command where it doesn't.
- **Every update is checked on the server:** the installed Scout accepts a new binary only with a signature covering its version, CPU type and hash, from the release key, and only if it's newer than itself. It checks the binary in memory and installs it from a folder only root can write. Through the narrow `sudo` rule, someone who took over Hive could install only genuine, current Scout releases, not a program of their own.
- **Scout never updates itself.** It runs unprivileged, and a root updater on every server would install whatever a release publishes without you deciding.
- **Updating is never urgent.** Hive accepts the current protocol version and the one before it. A Scout older than that is refused, and the reason shows in its log and in Beekeeper.

## Phase C: alerts, Macs and release

- **C1. Metric alerts:** email when a server stops reporting, or runs short of disk, memory or CPU for a while.
  - When two or more servers stop at once, you get one email about Hive's connection.
  - Nothing counts as stopped for a few minutes after Hive starts, the Mac wakes, or Hive's addresses change.
- **C2. The Hive Mac's metrics:** Hive reads its own Mac's figures directly, with nothing to install, and shows the Mac on the dashboard beside your servers. It's on by default, with a setting to turn it off.
  - Hive runs as your user and never takes back root, and macOS restricts what a non-root process can read about other users' processes. C2 finds out how much it hides, and shows what Hive can't read about individual processes as a single "other users" line if macOS gives a total.
  - The backup drive charts like any other disk. The existing low-space email stays, and the new disk alerts skip that drive.
  - There's no "stopped reporting" alert for the Hive Mac, since a Mac that has stopped can't send it. While Hive isn't running, the charts show a gap.
- **C3. Scout on other Macs:** the same install command, installed as a LaunchDaemon, from a signed and notarized universal binary. C3 decides whether it runs as root.
- **C4. README and release.**

## Room for log collection later

The plan's §10 keeps three choices so Scout can send logs in a later plan without a rewrite:

- **Each kind of data is separate.** Scout's routes and data are named for what they carry, so logs can arrive as a kind of their own on their own route.
- **Metrics go first.** Each kind of data gets its own buffer and limits, so a backlog of logs can't hold up metrics or push them out of the buffer.
- **What to collect is set on the server, never by Hive.** Otherwise someone who took over Hive could point Scout at any file on your servers.

Logs will still need their own decisions: wider read access (groups such as `systemd-journal` or `adm`), holding logs on disk while Hive is unreachable, and their own resource budget, storage and retention.

## Changes from the independent review

An independent reviewer read the plan, the summary and the code. Its findings were applied:

- **The pasted root command:** Beekeeper now builds it and checks every value from Hive, and Scout checks the SSH user name before writing a `sudo` rule. Before, a Hive taken over by someone else could have slipped a command into what you paste as root.
- **Updates:** the signature now covers version, CPU type and hash, the binary is checked in memory, and root never reads the folder Scout's unprivileged user can write.
- **Development:** a development signing key, so updates can be tested before a release exists.
- **Duplicates:** samples resent after a timeout are stored once.
- **Accuracy:**
  - the outage buffer keeps each minute's highest value, so spikes survive
  - grouped memory doesn't count shared memory over and over
  - the systemd setting that would have hidden a separate `/home` disk is fixed
- **Corrections:**
  - a more careful storage estimate, which led to shorter history (see "How long history is kept")
  - Compose services grouped by project
  - several servers can have enrollment windows open at once
  - a grace period after the Mac wakes, so it doesn't send "all servers stopped"
- **Slices split** where they were too big: signed releases (A5), servers without SSH details (B1), and containers into an engine slice (B7) and an interface slice (B8).
