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

**Done when:** with the test VM, stopping Scout sends a "stopped reporting" email and starting it a recovery email; filling a disk past its limit sends one email; cutting off both test VMs sends one email; sleeping and waking the Mac sends none; and the tests pass.
