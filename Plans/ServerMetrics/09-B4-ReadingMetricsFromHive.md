# B4. Reading metrics from Hive

**Phase B — Metrics in Beekeeper** · Engine, 1 session

References like §6 point to [00-Info.md](00-Info.md).

- **A series endpoint:** for a server, a range and a set of figures, the average and highest in each bucket, and the lowest where it's kept (§6). Hive picks the resolution (§6) and the bucket size so a range comes back as about 600 buckets, whatever its length, small enough for an iPhone over a slow connection.
- **The processes at a moment:** the 10-second sample nearest a time within the last 24 hours, or that hour's top 10 within 14 days.
- **A summary of every server** for the dashboard: its latest figures, whether it's reporting or its clock is ahead, and the last hour as a sparkline.
- **Disk forecasts:** each filesystem's rate of growth over the last week, from the hourly figures, and when it fills at that rate, or nothing when it's steady or shrinking.
- **Backup runs in a range,** for marking on charts, from the job log.
- **Live updates** carry each server's latest figures, coalesced: a listener that falls behind gets only the newest for each server, never a queue of them, and samples from a backlog are never sent. `Broadcaster` keeps a bounded queue for each listener, so metrics must not push out job progress for a slow device.
- **HiveKit** gets the types and the client calls. The API version goes up.

## Tests

- Bucketing a known series at each resolution, including ranges that cross from one resolution to another and gaps
- The forecast for growing, steady and shrinking series
- A slow listener gets the newest figures for each server and every job event
- A Scout's session is refused on every one of these routes

**Done when:** with a Scout in the test VM reporting to the development Hive, Beekeeper's Developer window shows a range, a moment's processes and live figures; and the tests pass.

## Session 1

Done: every route, the live updates, HiveKit's types and the tests, and the "done when". `Scripts/build-and-test.sh` passes. B4 is done.

Checked end to end (2026-11-24): Scout installed from Debug Beekeeper on the test VM's B3 Debian root, reporting to the development Hive. Through the Developer window: an hour's range in 10-second buckets, a day's in 3-minute ones and a week's in 20-minute ones; the processes nearest a moment as a sample, and `notKept` where nothing was; each server's live figures, moving on with every sample; the summary, with the VM reporting and two other servers stopped; forecasts, empty with too few hours; and a server's backup runs, one failed for a missing drive.

That check found two things, both fixed: a week's range read hours, since it reached Hive a few seconds older than a week, so minutes now count as kept for as long as pruning leaves them, an hour more; and a stopped server's sparkline showed the hour before it stopped as if current, so it's now the last hour by Hive's clock, moved by the server's offset.

What was decided along the way:

- **Routes** (`MetricsReading/`), each reached only by a device's session: `GET /metrics` for the dashboard's summaries, and under `/servers/<id>/metrics`, `series`, `processes`, `filesystem-forecasts` and `backup-runs`. A server whose metrics were removed still answers with its history. API version 4.
- **Figures are named** by `MetricsFigure`, such as `cpuUser` or `filesystem.available`, and a series comes back per subject (the server, then each filesystem, disk and interface), each with only the buckets something was kept in, so a missing one is a gap.
- **Buckets** are the smallest size from a fixed list that gives at most 600, and never finer than the finest resolution still kept at the range's start. Each stretch of the range is read from whichever resolution holds the most samples, so minutes from a Scout's backlog, which have no 10-second rows, fill the buckets they cover instead of showing as a gap.
- **A moment's processes** are the 10-second sample nearest it within 5 minutes, otherwise its hour's top groups, otherwise `notKept`.
- **Forecasts** use the least-squares slope of each filesystem's hourly available space over its newest week, need at least 6 hours, and give no date when it's steady, shrinking or more than a year off.
- **Backup runs** come from the job log, moved onto the server's clock by its last known offset.
- **Reporting** on the dashboard: waiting (nothing since its Scout enrolled), reporting, stopped (nothing for 3 minutes), clock ahead, or refused.
- **Live figures** go through `MetricsLiveBoard`, which keeps each server's newest and no queue. A device's stream gets a signal holding at most one change while unread, then writes every server's newest it hasn't seen, so figures never take room in `Broadcaster`'s queue from job events. Only a report whose newest sample is within a minute of when Scout sent it reaches the board, so a backlog never does.
- **The Developer window** shows each server's live figures under the response.

Follow-ups:

- **Processes in containers show a host user's name for their user ID,** such as Redis in a container as `hive-scout`, since Scout looks the ID up on the host. B7, which says which container each process is in, should show the ID instead for those.
