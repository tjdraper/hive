# B8. Containers and services in Beekeeper

**Phase B — Metrics in Beekeeper** · UI, 1 session

References like §7 point to [00-Info.md](00-Info.md). Load the `dataviz` skill before the first chart.

Built with you, from B7's figures:

- a containers chart on the server's page, by service
- a page for containers and services: live, grouped by service, with a choice to see each container, and its processes
- containers and services beside processes at a chosen moment
- unnamed containers by short ID and the commands running in them

**Done when:** on the test VM, you can tell which Swarm service a load came from an hour later, and see a cron job's cost under its service; you're happy with the pages in light and dark; and the build is clean.

## What B7 left for this slice

- **Routes** (API version 5): `GET /servers/<id>/metrics/containers?at=` for a `CgroupMoment`, the nearest sample's container groups and services or the hour's busiest, and `/containers/series?from=&to=` for a `CgroupSeries`, each group's average and highest CPU and memory in every bucket. Live updates carry each server's newest groups in `ServerMetricsLatest.containers` and `.services`. Process groups carry `place`: the container's group and ID, or the service.
- **Groups hold only the containers in Scout's top lists,** the top 10 by CPU and the top 10 by memory. A sample's `containerCount` counts every container, but a group's `containerCount` and figures count only those it was sent, so a Swarm service with 41 idle replicas can read as one. Show the server's count beside the groups, and don't present a group's figures as its whole service's.
- **`kind`:** `swarmService`, `composeService` (with `composeProject`, since each project has its own `db`), `container` for one with neither, and `unnamed` for one Hive couldn't name, by its short ID, with `commands` saying what it runs. Services have no `kind`.
- **Missing figures:** memory and I/O are nil where the kernel's controllers aren't on for the cgroup, as on the Alpine VM, which has only `cpu`. Systemd on cgroup v1 doesn't account for every service's CPU.
