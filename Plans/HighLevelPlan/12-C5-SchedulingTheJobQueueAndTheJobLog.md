# C5. Scheduling, the job queue and the job log

**Phase C — Backups in Hive** · Engine, 1 session

References like §11 point to [00-Info.md](00-Info.md). Look at `../site-backups/config/ScheduleFactory.php` and the queue in `../site-backups/src`.

- **Schedules** (§11): each job's times, in the Hive Mac's local time, worked out from the clock rather than timers, so sleep can't push them late without notice. A time skipped by a daylight saving change runs at the next valid moment, and a repeated hour runs once.
- **Missed runs:** if Hive was off or the Mac asleep at a scheduled time, the job runs once when Hive is back, not once for each time missed. Schedules are checked again on wake.
- **Waiting for the drive at start** (§4): overdue jobs wait a few minutes for the backup drive before failing.
- **The queue,** kept in Hive's store: one job runs at a time, a job already waiting isn't added twice, and Run Now and Cancel work through the API. Cancelling stops the child processes and leaves the snapshot partial for the next run.
- **After a crash or restart,** a run that was in progress is marked interrupted, and its partial snapshot is picked up next time.
- **Keeping the Mac awake** while a job runs, with a power assertion. Hive's state notes when the Mac is set to sleep, for Beekeeper to warn about.
- **Overdue jobs:** a job with no complete snapshot for longer than its schedule allows is marked overdue, for E2 to email about.
- **The job log** (§12): an entry for each run, with each directory and database, how long each took, how much was transferred and why anything failed. Through the API, with the newest first. Decide how long entries are kept (§19).
- **Progress events** from each run, for D3's WebSocket

## Tests

- Next run times across days, month ends and both daylight saving changes
- Missed runs while off or asleep run once
- A job can't be queued twice, and jobs never run at the same time
- An interrupted run is marked so after a restart, and its partial snapshot is reused
- A job is marked overdue at the right time, and no longer once it succeeds

**Done when:** the installed daemon runs a test job at its scheduled time against the test server; the job log shows each step; restarting the daemon mid-run marks the run interrupted and the next run reuses its partial snapshot; and the tests pass.
