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
