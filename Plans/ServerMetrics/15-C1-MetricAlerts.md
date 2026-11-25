# C1. Metric alerts

**Phase C — Alerts, Macs and release** · Mixed, 1–2 sessions

References like §8 point to [00-Info.md](00-Info.md). Read §12 on email alerts, and `Alerts/`, whose alert state and repeats this extends.

## Engine

- **Each alert in §8,** checked as samples arrive, with each limit's duration counted from samples, not wall-clock time, so a backlog arriving late doesn't fire alerts that were never true at the time
- **Stopped reporting** checked once a minute against each Scout's last-seen time, with a grace of a few minutes after Hive starts, after the Mac wakes, and after Hive's listen addresses change, since Scouts may still be backing off. Hive doesn't notice waking today: observe it with IOKit's power notifications.
- **Two or more servers at once:** when they stop within the same few minutes, one email about Hive's connection instead of one for each
- **Clock ahead** (§5) alerts as itself, never as stopped reporting
- **Repeats** follow Hive's existing rules (§12): a stopped server and a full disk again daily until resolved; a figure that comes and goes, such as CPU, once until it's cleared for an hour
- **Alert state in the store,** so a restart never sends one twice or forgets one
- **Limits for each server,** with §8's defaults, through the API, audited, and kept in recovery files

## UI

Built with you:

- each server's limits, with the defaults shown and a way back to them
- a server's current alerts on its card and page

## Tests

- Each alert fires after its duration and not before, clears, and repeats as described, across restarts
- A backlog from a Scout that was cut off doesn't fire alerts for the past
- Two servers stopping at once send one email; one stopping sends one about it
- No server counts as stopped during the grace after starting, waking or changing addresses

## Engine notes

Built in the first session, in `HiveCore/MetricAlerts/`:

- **Figures** (`FigureAlertCheck`) are checked on a report's newest sample, only while it's current, by averaging the duration before it from the 10-second samples kept. A duration needs samples back to its start, and a gap of over a minute leaves none. Memory and CPU end once every moment of the last hour, averaged the same way, was within the limits. A filesystem ends once it's 5 points under its limit and its forecast is more than twice its limit away.
- **Swapping in steadily** means more than 50 pages a second on average over the memory duration. Not yet a setting.
- **A restart** is noticed when the time the server started, from its uptime, moves more than 5 minutes later. It's noted on the Scout's row in the store.
- **Waking** is noticed by comparing the continuous clock with the suspending clock, rather than IOKit's power notifications: no callback that has to approve sleep, and tests can fake it (`ReportingGrace`, `MacSleepClock`). The grace is 5 minutes after starting, waking or the listening addresses changing.
- **Stopping together:** servers whose last reports are within a minute of each other are one email. A server that's gone quiet holds the email back while it might be stopping with them. A server that comes back while others it stopped with are still stopped isn't emailed about again until the whole group is back.
- **Limits** are `GET`/`PUT /servers/:id/metrics/alert-limits`, audited as a `ServerChange`, kept as JSON on the server's row (none for the defaults) and in recovery files. Current alerts are on each `ServerMetricsSummary`.

**Done when:** with the test VM, stopping Scout sends a "stopped reporting" email and starting it a recovery email; filling a disk past its limit sends one email; cutting off both test VMs sends one email; sleeping and waking the Mac sends none; and the tests pass.
