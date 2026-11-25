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

## Session 1

Built, and checked on Ivy with the development Hive (2026-11-25) on the Debian VM's Scout (B3 Debian root) and the Alpine VM's (Test: A4 Alpine). Light and dark approved on the Mac. The load was found from the stored samples minutes after it ran rather than an hour later; you checked the slice off without waiting, since an hour later reads the same samples.

- **The server's page** has a Containers, CPU chart by group and a Services, CPU chart, each a stacked area for the five busiest at their peak in the range, the rest as Others. Each links to the page below. Their figures are shares of one core, as the process lists' are, so 2 busy cores read 200%.
- **Containers and Services** (`ContainersPage`, a `figurePage` of kind `.cgroups`): Containers or Services, CPU and memory over the range, and below them a table, live every 10 seconds or at the moment clicked, with Show Live to go back. Containers show by service or each container. Selecting one shows its processes among the server's busiest. The note under the time gives the server's count, and says a group counts only those among the busiest when Scout sent fewer than all.
- **A group keeps its color** on every chart and list of the page (`CgroupHistory`), ranked by peak CPU then peak memory. A Compose service reads `project › service`.
- **The moment inspector** on the server's page chooses Processes, Containers or Services (`MomentCgroups`). Process groups say where they run, there and on the processes page's new Where column. `ProcessGroupPlace` gained `composeProject`, optional, so the API version stays at 5.
- **Unnamed containers** show by short ID with their commands under What. Memory reads "—" and its chart is left out where the kernel doesn't account for it, as on the Alpine VM.
- **Chart legends wrap** (`LegendLayout`), since a chart of groups has more entries than fit on a line.
- **Longer ranges** read containers from Hive's hours after a day, so `MetricsTimeline` takes the series' own bucket size.

Checked so far:

- **A load in a Swarm service:** a busy loop in `scout-test_cache`'s container, 06:59 to 07:03, showed as a 100% block on that group in both charts. Clicking it showed the sample at 07:01:20, `scout-test_cache` at 100% with 3 processes, and selecting it showed `sh` at 100% beside `redis-server`.
- **A cron job:** `cron.service` spikes to about 50% each minute on the Services chart, and reads 50% in the samples that catch it.
- **Without `docker` access:** the Alpine VM's two containers show as `836895074d6a` running `redis-server` and `e51c2cd85949` running `nginx`.
- **The build:** `Scripts/build-and-test.sh` is clean. `ContainerNamingTests` now checks that two Compose projects' `db` processes each name their project.
