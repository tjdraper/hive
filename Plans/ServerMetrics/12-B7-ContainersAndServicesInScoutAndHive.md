# B7. Containers and services in Scout and Hive

**Phase B — Metrics in Beekeeper** · Engine, 1–2 sessions

References like §4 point to [00-Info.md](00-Info.md). Read §12 on SSH and Docker, and `ContainerListReader`, for how Hive lists containers today.

Which site is using the server, when every site runs the same `nginx` and `php-fpm`, and what short-lived work costs (§4). B8 shows it.

## Scout

- **Cgroups** under `/sys/fs/cgroup`, cgroup v2 first and v1 where a server still has it:
  - Docker containers, for both of Docker's cgroup drivers (`system.slice/docker-<id>.scope` and `docker/<id>`), and Podman's too if it's no more than another path
  - systemd services (`system.slice/<name>.service`)
- **For each:** its CPU share since the last sample, memory in use (leaving out cache the kernel can reclaim, as `docker stats` does), I/O bytes and its number of processes
- **Sent as the top 10 by CPU and by memory** of each, with their counts, in the same sample as the rest
- **Each process's container or service** from `/proc/<pid>/cgroup`, in the process lists
- **Still within §3's budget** on a server running 50 containers

## Hive

- **Naming containers:** when a sample carries a container ID Hive hasn't named, a read-only `docker ps` over SSH, giving each container's name and its Swarm service, or Compose project and service, at most once a minute per server. Container IDs are checked as 64 hex digits and never go into the command.
- **Which servers can be asked:** the dump code has no check for `docker` access, it just fails with `dockerUnavailable`. Record per server when `docker ps` fails, and try again only daily or when its SSH details change.
- **Names kept in the metrics database,** so history keeps its names after a container is gone
- **Grouping:** Swarm replicas by service, so `buzzingpixel_db.1.<id>` shows as `buzzingpixel_db`; Compose by project and service, so each project's `db` stays its own
- **Storage** (§6): the top lists with each sample, and each service's hourly figures for 90 days. Measure what it adds on a server with many containers, and correct §6.
- **B4's API** gains containers and services at a moment, each one's series over a range, and their latest figures in live updates.
- **Names never go in the system log** (§9).

## Tests

- Reading each cgroup layout from captured files, including a container that stopped between listing and reading
- Parsing `docker ps` output, including containers without a service label and Compose projects sharing service names
- Grouping replicas, and keeping a service's history across replaced containers
- A container ID that isn't 64 hex digits is refused
- A server where `docker ps` fails shows IDs and commands, and isn't asked again every minute

**Done when:** in the test VM with Docker in Swarm mode, the Developer window shows each Swarm service's CPU and memory by name, and a load made inside one service shows on it; a cron job's CPU shows under its systemd service; a server without `docker` access shows IDs and commands; and the tests pass.

## Session 1

Done: the whole slice, and the "done when".

Checked on Ivy with the development Hive (2026-11-25), through the Developer window:

- **Swarm services by name:** on the Debian VM's Scout (B3 Debian root), Hive named all 9 containers, and the groups read `scout-test_web`, `scout-test_cache` and the rest. A busy loop run inside `scout-test_cache`'s container showed as about 100% CPU on that group.
- **A cron job:** `/etc/cron.d/scout-test-cron` runs a 5-second busy loop each minute, and `cron.service` showed about 50% CPU, though no process list ever caught it.
- **Without `docker` access:** on the Alpine VM (Test: A4 Alpine), Hive's user can't run `docker`, so `docker ps` failed once and wasn't asked again. Its two containers showed as `unnamed` by short ID, running `redis-server` and `nginx`.
- **The tests pass,** and `Scripts/build-and-test.sh` is clean.

What was decided along the way:

- **Scout** (`ScoutCore/Cgroups/`): `CgroupLayout` finds cgroup v2, or v1's `systemd` or `cpuacct` hierarchy, and lists `system.slice`'s services and the slices in it, Docker's containers under both drivers, and Podman's `libpod-` scopes in `machine.slice`. `CgroupReader` keeps up to 100 cgroups' files open between samples, and counts all of a new or recreated cgroup's work, so a container started between samples isn't lost. Memory is the cgroup's less its `inactive_file`, as `docker stats` gives it.
- **Each process group's place** comes from the cgroup whose `cgroup.procs` lists it, so groups are by command, user and container or service. A container's users show by number, since the host's names for them are another system's.
- **Protocol version 2,** Scout 0.3.0: samples carry `containers` and `services`, each the top 10 by CPU and by memory with a count of all, and process groups carry `containerID` or `service`. Hive refuses more than 20 of each, more than 5 commands each, and a container ID that isn't 64 lowercase hex digits.
- **Naming** (`ContainerNaming/`): `ContainerListing` is a constant `docker ps` command, so nothing Scout sends goes into it. `ContainerNamingWorkflow` runs on its own task after a report is kept, at most once a minute per server, and only when a sample carries an ID Hive hasn't seen. IDs `docker ps` doesn't list are kept without a name so they aren't asked about again. After a failure it asks again only a day later, or once the server's SSH details change. Names are pruned 2 days after they were last seen.
- **Storage:** the raw figures go with each 10-second sample, compressed, for a day, keyed by container ID so a name learned later still applies. Each hour keeps its grouped busiest, with average and highest, for 90 days.
- **Grouping** (`CgroupGrouping`): by Swarm service, then Compose project and service, then container name, then `unnamed` with the short ID and its commands.
- **Hive's API is version 5** (oldest compatible 4): a moment's groups and services, their series over a range, and the newest in live updates. B8's file lists what it needs from them.

Measured on the Debian VM with 50 containers and about 365 processes, over 5 minutes each:

| Scout build | CPU of one core | Resident memory |
| --- | --- | --- |
| Parsing cgroup files as strings | 0.160–0.170% | |
| Parsing them as bytes (kept) | 0.143% | 21.5 MB, 26.3 MB at its highest |

§3's budget is 0.15%, and A1 measured 0.100% with 9 containers. Most of what's left is the kernel's: reading every cgroup's files every 10 seconds costs it about 0.03% of a core on its own. Storage came to 1.45 KB a sample, so about 15 MB for a day of samples, and a scratch run of 90 days of hours to about 9 MB. §6 is corrected.

That check found a bug, now fixed: `.map(Double.init)` on an optional `UInt64` picked `Double(bitPattern:)`, so groups' memory read as nearly zero. `ContainerNamingTests` now checks a group's memory.

Scout's tests read two new captures, `debian-12-swarm` (systemd's driver, 9 containers) and `alpine-3.22-docker` (cgroupfs's driver, only the `cpu` controller, so no memory or I/O).

Follow-ups:

- **Groups count only the containers in Scout's top lists,** so a Swarm service with many idle replicas can read as fewer. B8 has the note.
- **0.143% leaves little room** under the budget. A server with many more processes or containers could pass it; reading fewer cgroup files for idle containers would be the place to save.
