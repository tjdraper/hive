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
