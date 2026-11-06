# C6. Retention and quotas

**Phase C — Backups in Hive** · Engine, 1–2 sessions

References like §10 point to [00-Info.md](00-Info.md). Look at `../site-backups/src/Backup/ApplyRetentionCommand.php` and `ApplyMonthlyBackupCommand.php` for what this replaces.

Retention must never remove the wrong snapshot (AGENTS.md). This slice is mostly tests.

- **Tiers** (§10): which snapshots a job keeps, as a pure function of its snapshots, their dates and its tiers. Daily tiers count days that have a snapshot, not calendar days, so a long outage never ages out history. Settle the exact rules: several runs on one day, month boundaries, and partial snapshots. A failed run's partial folder goes once a newer snapshot is complete. Choose defaults (§19).
- **Counting space** as it's used on the drive: files are grouped by inode, so a file hard-linked into several snapshots counts once. For each snapshot, how much removing it would free, and the total for each server. Kept in the catalog, and recounted only where a run or removal changed something, since a full recount of large trees over USB could take hours.
- **Quotas** (§10): when a server is over, its oldest daily snapshots are removed first, across all its jobs, until it fits. Monthly snapshots and the newest complete snapshot of each job are never removed for a quota. If it still doesn't fit, the server is marked over quota, for E2 to email about.
- **Lowering a quota or tiers:** nothing is removed because of the change until it's confirmed (D4)
- **Defaults:** C1 takes tiers and a quota with every job and server, and allows no quota. Choose the defaults D2 offers, and whether no quota stays allowed.
- **After a restore:** retention and quotas don't run until you confirm in Beekeeper (F3)
- **Removing safely:** a snapshot is removed only if it's in the catalog, its real path is inside its job's folder on the backup drive, and nothing is writing to it. It's renamed first, so a restart in the middle finishes the removal instead of leaving half a snapshot. Folders copied from servers without write permission get it back before removal. Symbolic links inside a snapshot are removed, never followed.
- **When it runs:** after each run, and once a day
- **Logging and the job log:** what was removed and why, and how much space it freed

- **From C3:** a partial can be left behind for good, besides a failed run's: when the job's directories changed since, the next run starts a new partial instead of picking it up. Snapshots are in the `snapshot` table with their drive UUID and folder names. A folder a server sent without write permission was writable on the drive in C3, since `--fake-super` keeps the server's mode in an attribute instead. Check files and deeper trees before relying on it.

## Tests

- Tiers keep exactly the right snapshots across days, months, several runs a day and daylight saving changes
- A job that failed for 30 days keeps the same daily snapshots it had when it started failing
- Space counted for hard-linked trees in temporary folders matches what removing them frees
- The quota never removes a monthly snapshot or the newest complete snapshot of any job, and marks the server over quota when that's all that's left
- Nothing outside the job's folder is ever removed, including through a symbolic link, `..` in a name, or a catalog entry pointing elsewhere
- A snapshot being written is never removed
- A snapshot with read-only folders is removed completely
- A removal interrupted halfway is finished on the next start

**Done when:** the tests pass, and on the test drive, setting the test server's quota below what it uses removes its oldest daily snapshots, keeps the monthly and newest ones, and frees the space Hive said it would.
