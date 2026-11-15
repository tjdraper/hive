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
