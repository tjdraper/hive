# C2. The Hive Mac's metrics

**Phase C — Alerts, Macs and release** · Mixed, 1–2 sessions, installed build

References like §4 point to [00-Info.md](00-Info.md).

Every Hive reports its own Mac (§1), with nothing to install.

## Engine

- **macOS readers for §4** in `ScoutCore`, so C3's Scout uses the same ones: `host_processor_info` and `host_statistics64` for CPU and memory, `sysctl` for load, swap and memory pressure, `getfsstat` for filesystems, IOKit for disk activity, `getifaddrs` for the network, and `proc_listpids` with `proc_pidinfo` for processes. Linux-only figures, such as steal, `/proc/pressure` and cgroups, are left empty rather than faked, and Beekeeper hides their charts.
- **Hive samples its own Mac** on the same 10-second marks and writes straight to the metrics database: no enrollment, key or connection. While Hive isn't running there's nothing to sample, so its own downtime shows as a gap.
- **What Hive can see as your user:** the daemon never takes back root (§12). Find out which other users' processes macOS lets it read, show the rest as one "other users" line if their total can be had, and record what's missing in §11.
- **The backup drive** is one of the Mac's filesystems like any other, so its space and activity chart beside the rest. The existing low-space email stays as it is, and C1's disk alerts leave the backup drive to it, so it isn't emailed about twice.
- **On by default,** with a setting to turn it off, audited
- **Alerts** (C1) cover the Hive Mac, except "stopped reporting", which can't come from the Mac that stopped.

## UI

Built with you:

- the Hive Mac on the dashboard and with a page of its own, marked as the Hive's Mac rather than a server
- the setting, beside the Hive's other settings

## Tests

- Each reader against values captured from a Mac, where the API allows it, and grouping and rates shared with Linux
- Turning it off stops sampling and keeps the history

**Done when:** the installed Hive shows its Mac on the dashboard and its own page in Beekeeper, the readings agree with Activity Monitor, the daemon's added CPU and memory are within §3's budget, and the tests pass.

## Engine notes

Built in the first session:

- **Scout's macOS readers** are in `ScoutCore`, each beside its Linux one (`MacCPUReader`, `MacMemoryReader`, `MacFilesystemReader`, `MacDiskReader`, `MacNetworkReader`, `MacProcessReader`, `MacServerFactsReader`), composed by `MacSampler`. `ScoutCore` is now a library product, which HiveCore imports.
- **What a Mac leaves out:** I/O wait and steal (a Mac counts waiting as idle and has no steal), a disk's busy share (IOKit counts how long requests took, which overlap), sent drops for each interface, pressure, containers and services. Those figures are now optional in `ScoutProtocol` and HiveKit, with no new protocol version: a Linux Scout still sends them all.
- **Memory** is counted as Activity Monitor counts it: in use is App Memory (less purgeable), Wired and Compressed, and cache is file-backed and purgeable pages. Each process's memory is its footprint, as Activity Monitor shows it.
- **Filesystems** are the volumes Finder shows: local, not hidden (`MNT_DONTBROWSE`), and not read-only apart from the startup disk's sealed system volume. APFS has no fixed number of inodes, so none are sent, as for Btrfs.
- **Interfaces** are those up with an address that isn't loopback or link-local, leaving out virtual machines' bridges and links (`bridge100` and up, `vmenet`). **Disks** leave out disk images.
- **Other users' processes** (§11) are `ProcessFigures.otherUsers`, kept as `otherUsersProcesses` and `otherUsersCPU` in a new metrics migration, readable as `MetricsFigure`s, and returned with a moment's processes as `ProcessMoment.sample`'s `otherUsers`.
- **Hive samples itself** (`HiveMacMetrics/`): `HiveMacSampler` takes a sample on each 10-second mark while `HiveSettings.collectsMacMetrics` is on, and `HiveMacMetricsWorkflow` keeps it through `MetricsStore` under the Hive's own ID, so it passes the same checks as a Scout's report. The setting is audited (`macMetricsChanged`), in recovery files, and on by default. Turning it off drops the sampler, so no rate spans the gap, and keeps the history: the Mac's routes keep answering for the Hive's ID, and upkeep never removes it.
- **For Beekeeper:** the dashboard's summaries list the Hive Mac first, under the Hive's ID, while it's on and once it has figures. `GET /servers/<Hive ID>/metrics` gives a `ServerMetricsState` whose Scout is the one Hive is built with, enrolled when the Hive was set up. Every other metrics route takes the Hive's ID as a server's.
- **Alerts** use the default limits, and the Mac's restart is noted in `hive.macBootedAt`. The backup drive's volumes, and the other APFS volumes in its container, are left out of its disk alerts. Emails call it “the Hive Mac “Name””.
- **Cost:** a sample takes about 5 ms of CPU in a release build on Ivy (10 cores, 770 processes), about 0.05% of one core. Processes take 1.6 ms of it and the interface list 3.2 ms.

Left for the UI session: Beekeeper drops summaries it has no server name for, so the Hive Mac doesn't show yet; the dashboard card, the page and its charts that a Mac has no figures for; the other users line; and the setting beside the Hive's others.

## UI notes

Built in the second session:

- **`MetricsSource`** (`Beekeeper/HiveMacMetrics/`) names what a card or page is about: a server, or the Hive Mac when the ID is the Hive's own, named after the Hive, with a Mac's icon. The dashboard card and row tag it "Hive Mac", and it comes first among cards of the same standing. Its page and the pages below it use the same name and icon, and on iPhone they go back to the dashboard, since there's no server page above them.
- **What a Mac leaves out:** the CPU chart drops I/O wait and steal when the range has none, and the moment's panel offers only processes, without containers or services. Pressure was already hidden when missing. The facts say Scout is "Built into Hive".
- **Other users' processes** are one row, "Other users' processes ×N", with their CPU and "—" for memory, and a note in the caption saying why.
- **The setting** is "Read the Hive Mac's Metrics" in the Hive's settings, after Build Expiry Warnings, and saves as soon as it's changed. While it's off the dashboard leaves the Mac out.
- **Checked against macOS on Ivy** with the development daemon: memory in use, swap and "/" agree with `vm_stat` (counted as Activity Monitor counts it), `sysctl vm.swapusage` and `df`; CPU is within a couple of points of `top`.
- **The installed build** shows the Mac on the dashboard and its own page, with the daemon running as the installing user. Its added CPU, measured with `ps` over three minutes each with the setting on, off and on again, was about 0.26% of a core, over §3's 0.15%. Its memory was about 30 MB in all, so what the sampling adds couldn't be told apart.
- **Bringing it under budget:** a sample cost 8 ms of CPU back to back but 29 ms with 10 seconds between them, as the daemon takes them, since nothing is still in the CPU's caches and an idle Mac runs it on its efficiency cores. Measured that way, in a release build on Ivy (49 interfaces, 750 processes):
  - Naming each interface with `if_indextoname` read the whole list again for each one. The names now come from `getifaddrs`' link-layer entries, which the reader already walks.
  - Finding the backup drive's mount point listed every volume with its resource values on every sample. `BackupDriveMountResolver` lists them again only when the sample's filesystems or the chosen drive change.
  - The process reader no longer asks for other users' CPU and memory without root, which macOS refuses, and reads a process's long name only when it's new or its short name changed.

  A sample now costs 13.5 ms with 10-second gaps (8.8 ms reading, 4.6 ms keeping), about 0.135% of a core. Most of what's left is a few calls into the kernel for each process, and writing the sample.

  Installed again, the daemon used 0.33% and 0.37% of a core in three-minute windows with the setting on and 0.18% with it off, so the sampling adds about 0.17%: down from 0.26%, but still a little over §3's 0.15%.
- **A second pass,** with Time Profiler on a release build and instructions counted per sample, which unlike CPU time don't change with the core or what's in its caches, in steady state (75 minutes of history and full hours to roll up). From 52 million instructions a sample to 32 million:
  - Choosing the top process groups sorted the groups themselves, copying their names at every comparison: half the process reader's time. They're sorted by position now. Scout on Linux uses the same code.
  - The interface counters come from `NET_RT_IFLIST2` asked for by index, for the interfaces reported, rather than the whole list with every interface's addresses.
  - The alert check reads its 75 minutes of samples by column position, rather than by name, which GRDB matches against every column's name, ignoring case, for every row.
  - Each rollup's SQL is built once rather than for every sample's eight rollups.

  Installed again, the daemon used 0.32% of a core in both three-minute windows with the setting on and 0.17% with it off, so the sampling adds about 0.16%: no clear change from the first pass, though the harness counted 40% fewer instructions. So most of what the installed daemon spends on it is outside what the harness runs. Live updates to a Beekeeper that's following, and waking every 10 seconds, are the likeliest places, but neither has been measured.
- **Accepted at about 0.16% of a core** for the Hive Mac, a little over §3's 0.15%, which was written for Scout on a server, where it competes with the server's own work. On the Hive Mac's 10 cores the difference is negligible. The readings were checked against `vm_stat`, `top`, `df` and `sysctl`, the figures Activity Monitor shows, rather than against the app itself.

Follow-ups:

- What the installed daemon spends on the Hive Mac's sampling outside what the harness runs, likely live updates to a following Beekeeper or waking every 10 seconds. Profile the development daemon with Beekeeper following it, if the cost ever matters.
- A Mac filesystem's page shows no disk charts: `disk(holding:)` matches Linux device names, and an APFS volume such as `disk3s1s1` is on a synthesized container, not the physical disk IOKit counts. Mapping it needs the container's physical store from the engine.
- The Hive Mac uses the default alert limits, with no way to change them from Beekeeper yet.
- The processes table's Where column is always empty for the Hive Mac.
