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

- **From C4:** `BackupRun` also has `databases`, a `DatabaseRun` for each dump, with its own failure reasons. A dump is a single `ssh`, so cancelling stops it like rsync, and its file is removed.
- **From C4:** `Scripts/test-drive.sh` makes one image, which the installed Hive and the development daemon can't share, since each marks it as its own. C4 gave the development daemon a scratch image by hand. A second image for the development daemon, or a name argument, would save that.
- **From C3:** `BackupRunCoordinator` runs Run Now one at a time and keeps each job's latest `BackupRun` in memory, read with `GET /jobs/<id>/run`. The queue replaces it, and the job log keeps each `BackupRun` with its `DirectoryRun`s. Cancelling a task running `BackupRunWorkflow` already stops rsync and ends the run as `cancelled`, leaving its partial.

## Tests

- Next run times across days, month ends and both daylight saving changes
- Missed runs while off or asleep run once
- A job can't be queued twice, and jobs never run at the same time
- An interrupted run is marked so after a restart, and its partial snapshot is reused
- A job is marked overdue at the right time, and no longer once it succeeds

**Decisions (2026-11-06):**

- **Schedules** (`Scheduling/`): each job's next run is kept in `jobSchedule`, with the times and time zone it was worked out for. `BackupScheduler` compares it with the wall clock every 30 seconds, so a Mac waking from sleep is noticed within 30 seconds without a wake notification. A time that has passed queues the job once, however many passed. A new job, or one whose times or the Mac's time zone changed, gets its next time without running for one already past. A time the clocks skip runs at the first moment after the gap (2:30 runs at 3:00), and a repeated time runs on its first pass.
- **The queue** (`BackupRuns/`): `queuedRun` holds one row per job, so a job waiting or running can't be queued again. Run Now goes ahead of scheduled runs; otherwise runs go in the order queued. `POST /jobs/<id>/run` answers 202 with the job's `JobStatus`, or 409 while it's waiting or running. `DELETE` takes a waiting run out of the queue or stops a running one, recorded as `backupRunCancelled`. `GET` gives the job's `JobStatus`, and `GET /job-status` every job's: idle, waiting or running, the run going now and its step, the last run, the last snapshot, the next run and whether it's overdue.
- **After a restart,** before Hive listens, unfinished runs are marked `interrupted` and their jobs queued again as `afterInterruption`, which picks up the partial. A run queued that way isn't queued again if it's interrupted too, so a run that brings Hive down can't do it on every start. A run saves its progress to the job log as each directory and database finishes, so an interrupted entry shows what was done.
- **Waiting for the drive:** for five minutes after Hive starts, a run whose drive is missing checks again every 10 seconds before going on. Later runs fail with `driveMissing` at once.
- **Keeping the Mac awake:** a `PreventUserIdleSystemSleep` assertion named "Hive is running a backup", held for each run. `HiveOverview.macSleep` reads the idle sleep timer from `pmset -g`, since macOS has no public API for it.
- **Overdue:** a job is overdue three hours after the first of its times following its last complete snapshot, or following when it was added. The three hours leave room for a run that starts behind every other job due at the same time. A running job isn't overdue, since a first run can take hours. `JobStatus.overdueSince` gives it, and `OverdueCheck` is there for E2.
- **The job log** (`JobLog/`): `jobLogEntry`, with the server and job names copied in so entries outlive both. `GET /job-log`, newest first, with `before`, `limit`, `job` and `server`. Entries are kept for a year and pruned once a day. `BackupRun` gains `pickedUpPartialSnapshot`, and `BackupFailure` gains `interrupted`.
- **Events for D3:** `BackupRunCoordinator.events.listen()` gives each run event as it happens: queued, left the queue, started, each step (waiting for the drive, checking directories, pulling a folder, dumping a database, completing), progress as each directory and database finishes, and finished.
- **Children in Hive's process group:** the first installed check found that stopping the daemon mid-run left its rsync and ssh-agent running, adopted by launchd, with the rsync still writing into the partial snapshot the restarted Hive's run picked up. Foundation's `Process` gives each child a process group of its own, and launchd only kills what's left in the daemon's own group when it exits. `SpawnedProcess` starts children with `posix_spawn` in Hive's group instead, for `ChildProcess` and `SSHAgent`, so they end with Hive however it ends. On SIGTERM, Hive also stops the run going now first, giving rsync its two-second grace, starts nothing more, and leaves the run for the next start to mark interrupted.
- **Not done:** C4's suggestion of a second test drive image for the development daemon.

**Result (2026-11-06):** the tests pass, including next run times across days, month and year ends, a leap day and both daylight saving changes in New York's time zone. In the installed build, against the test server and test drive: on its first start the daemon migrated the store and worked out both jobs' next runs without running them. "Example site", moved to 18:50, ran on its own at 18:50:09, and its job log entry shows the scheduled trigger and each directory with its time, files and bytes. With 100,000 small files added, the daemon was sent SIGTERM partway through its 21:45 run: rsync stopped at once, nothing of Hive's was left running, and the restarted daemon marked the run `interrupted` and ran the job again as `afterInterruption`, which picked up the partial and copied only the 92,764 files it lacked into a complete snapshot holding all 100,000. The first try at this, before `SpawnedProcess`, found the leftover rsync and ssh-agent described above. The power assertion was checked only by the tests, not watched in `pmset -g assertions` during an installed run. The job's time was left at 21:45, and the test files were removed from the test server.

**Done when:** the installed daemon runs a test job at its scheduled time against the test server; the job log shows each step; restarting the daemon mid-run marks the run interrupted and the next run reuses its partial snapshot; and the tests pass.
