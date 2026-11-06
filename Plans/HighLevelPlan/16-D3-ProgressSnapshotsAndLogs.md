# D3. Progress, snapshots and logs

**Phase D — Managing backups in Beekeeper (Mac)** · Mixed, 1–2 sessions

References like §12 point to [00-Info.md](00-Info.md).

## Engine

- **The WebSocket** (§3): job states, progress and new job log entries, sent as they happen, after signing in with the session token. Beekeeper reconnects on its own, and keeps one for each connected Hive.
- **Snapshots through the API:** each job's snapshots with their date, whether complete, and how much removing each would free (C6), plus each server's total against its quota

- **From C3:** the catalog is the `snapshot` table, and `GET /jobs/<id>/run` gives the latest run until C5's job log.

## UI

Built with you:

- **Status** for each server and job: last run and its result, next run, overdue, and progress while running, with Run Now and Cancel
- **A job's snapshots,** with sizes, and on the Hive Mac, Show in Finder, with a reminder to copy files out rather than open them in place (§9)
- **The job log,** filterable by server and job, with failures easy to find
- **The audit log** (B3) next to it
- **A warning when the Hive Mac is set to sleep** (C5)

**Done when:** in the installed builds, a run started with Run Now shows its progress live in Beekeeper and lands in the job log; Cancel stops it; Beekeeper picks up again after the daemon restarts; and a job's snapshots list matches the test drive.
