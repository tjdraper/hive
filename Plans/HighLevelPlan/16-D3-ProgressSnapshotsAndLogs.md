# D3. Progress, snapshots and logs

**Phase D — Managing backups in Beekeeper (Mac)** · Mixed, 1–2 sessions

References like §12 point to [00-Info.md](00-Info.md).

## Engine

- **Live updates** (§3): job states, progress and new job log entries, sent as they happen, after signing in with the session token. Beekeeper reconnects on its own, and keeps one for each connected Hive.
- **Snapshots through the API:** each job's snapshots with their date, whether complete, and how much removing each would free (C6), plus each server's total against its quota

- **From C3:** the catalog is the `snapshot` table, and `GET /jobs/<id>/run` gives the latest run until C5's job log.
- **From C4:** a run reports each database's dump with its time, bytes dumped and stored, and failure. The database failures each need words in Beekeeper, such as "the database turned down the password" for `databaseLoginRefused`.
- **From C6:** `snapshot.freesBytes` is what removing each frees, nil for a moment after a change nearby until the pass recounts it, and `jobSpace.usedBytes` is each job's space on a drive, each file once. A server's total is the sum of its jobs'. `GET /job-log` gives `JobLogEntry`: `.run(RunLogEntry)` or `.removal(RemovalLogEntry)`, with each snapshot removed, its reason and the bytes it freed, and any that couldn't be removed and why. `RunEvent` and `JobStatus` carry `RunLogEntry`.
- **From C5:** `BackupRunCoordinator.events.listen()` is the WebSocket's source: `RunEvent`s for a run queued, leaving the queue, starting, each `RunStep`, progress as each directory and database finishes, and finishing. `GET /job-status` gives every job's `JobStatus` (state, the run going now and its step, last run, last snapshot, next run, overdue), for Beekeeper to start from before events arrive. `GET /job-log` takes `before`, `limit`, `job` and `server`. Run Now is `POST /jobs/<id>/run` (409 while waiting or running) and Cancel is `DELETE`. `HiveOverview.macSleep` says whether the Mac sleeps when idle. A run that picked up a partial snapshot says so in `pickedUpPartialSnapshot`, and `interrupted` means Hive restarted during the run.

## UI

Built with you:

- **Status** for each server and job: last run and its result, next run, overdue, and progress while running, with Run Now and Cancel
- **A job's snapshots,** with sizes, and on the Hive Mac, Show in Finder, with a reminder to copy files out rather than open them in place (§9)
- **The job log,** filterable by server and job, with failures easy to find
- **The audit log** (B3) next to it
- **A warning when the Hive Mac is set to sleep** (C5)

- **From D2:** `GET /servers/<id>/space` already gives a server's total on the chosen drive as `ServerSpace`, nil while a job with snapshots there isn't counted. The server page and the server editor show it beside the quota. The job page (`JobDetail`) shows only the job's configuration, with room for its status and snapshots, and the server page lists its jobs in `ServerJobsSection`.
- **From D1:** the sidebar's server rows and the Overview's server list show only "Not set up yet" for now; status goes beside them. The Overview polls `/backup-drive` every 15 seconds for its warning, and `MainWindow` refreshes every Hive every 30, both of which the WebSocket can replace.

**Decisions (2026-11-09):**

- **Live updates are a response Hive keeps open,** `GET /live-updates`, one `LiveUpdate` JSON line at a time, in place of a WebSocket. It passes through `RequestGate` like every other request, and Hummingbird's test client can test it without a port. Hummingbird's WebSocket channel would also have dropped the listener's 30-second cutoff for a connection that never sends a request. The first line is every job's `JobStatus`, then `RunEvent`s as they happen, with the job's status after it's queued, leaves the queue, starts or finishes, and a heartbeat every 15 seconds. Each line is checked against the session first: the response ends within a heartbeat once the session runs out, a revoked device gets nothing more, and Hive stopping ends it at once. Retention's removals are a `RunEvent` too.
- **TLS waits a second, not five, for a closing client's close_notify.** URLSession never sends one, so with live updates open the daemon couldn't stop within launchd's 5 seconds and was killed, which would also cut short a run's cleanup.
- **Snapshots:** `GET /jobs/<id>/snapshots` lists the job's snapshots on the chosen drive, newest first, with each one's state and what removing it frees, the job's total, and its folder on the Hive Mac while the drive is mounted. `GET /job-log?problems=true` keeps failed runs, but not cancelled ones, and removals that left a snapshot behind.
- **In Beekeeper,** the job page starts with its status: what the run is doing, with a progress bar over its directories and databases, the last and next runs, overdue, and Run Now or Cancel. Its snapshots end the page, each with what it alone takes, Incomplete and Being removed tags, and on the Hive Mac a Show in Finder button with the reminder to copy files out. The Job Log is a Hive page beside the Audit Log, filtered by server, job and problems, with each run's directories and databases on request. The sidebar, the server page and the Overview mark a job or server only when it needs a look: running, waiting, failed or overdue.
- **Times are shown as times** ("Today at 7:15 PM"), except the Overview's "Backed up 2 hours ago" per server, which updates each minute and shows the time on hover.
- **A cancelled request no longer marks a Hive offline.** URLSession reports a request cancelled by a view reloading as a `URLError`, which `HiveLink` took for the Hive being unreachable.
- **`JobStatePreviews.swift`** previews every job status, badge and snapshot row with made-up runs.
- **A job's directories are stacked in its editor,** each path on a full-width line that wraps above its folder, since long paths were cut off in half-width columns.

**Result (2026-11-09):** the tests pass. In the installed builds, Run Now showed its progress live and landed in the job log, Cancel stopped it, Beekeeper picked up again after the daemon restarted, and the job's snapshots matched the drive.

**Done when:** in the installed builds, a run started with Run Now shows its progress live in Beekeeper and lands in the job log; Cancel stops it; Beekeeper picks up again after the daemon restarts; and a job's snapshots list matches the test drive.
