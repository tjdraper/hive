# C3. Directory snapshots

**Phase C — Backups in Hive** · Engine, 1–2 sessions, installed build

References like §9 point to [00-Info.md](00-Info.md). Look at `../site-backups/src/Backup/BackupRsyncDirectory.php` and `BackupDirHandler.php`.

## The backup drive

- **Choosing it through the API:** Hive lists mounted volumes with their name, format, size and free space, and records the chosen one's volume UUID. It refuses anything but case-sensitive APFS (§9).
- **Hive's folder** on the drive, `Hive/`, holds a marker with the Hive ID, so a drive from another Hive is never written to by mistake.
- **Finding it on every run by UUID.** When it isn't mounted, or its marker doesn't match, the run fails without writing anything (§9).
- **The test drive:** a script that creates and mounts a case-sensitive APFS disk image for development (Part 2).

## rsync

- **Bundled rsync 3.x** (§11): a script that builds it from source at a fixed version, checks the download's checksum, and builds it with extended attribute support. It's embedded in `Hive.app`, signed with the hardened runtime, and used by tests too. Its license and source location go in the repository for I1.
- **An `RsyncRunner`** that pulls each directory with `--archive --delete --fake-super`, `--link-dest` pointing at the job's last complete snapshot, and `--timeout`, over `ssh` built by C2's runner. Never `--inplace` or `--append` (§9). Run it inside C2's `SSHSession.with`, passing `SSHCommand.options` as `-e`; rsync splits `-e` on spaces, which the run folder's path in the user's temporary folder doesn't have, so check that rather than assume it. `ChildProcess` lives in `SSH/` until rsync needs it too. The agent drops the key after two minutes, which is fine since `ssh` signs in once at the start. Exit code 24, files that vanished mid-run, is a warning in the job log, not a failure.
- **A missing or empty source folder fails the run** (§9). Settle how to tell an empty folder from an unreachable one.

## Snapshots

- **A snapshot's life** (§9): created as `<date-time>.partial`, each directory pulled under `files/`, the manifest written, then renamed. A failed run's partial folder is picked up by the next run.
- **Server and job folders** are named once, from the name plus a short ID, and never renamed (§9)
- **Manifests,** in a versioned JSON format (§9)
- **The catalog of snapshots** in Hive's store, updated as each one is made
- **Removing a job or server** removes its configuration rows through foreign keys (C1). The catalog must not reference `backupJob` or `server` with a cascading delete, since their snapshots stay (§10).
- **Run now** through the API, to back up a job's directories. C5 moves it onto the queue.
- **Logging:** each step, its duration and how much it transferred. Never paths.

## Tests

Run against local temporary folders, with `rsync` but no `ssh`:

- Owners and groups are kept with `--fake-super`, and an unchanged file still links when Hive can't set its owner
- In a second snapshot, an unchanged file is a hard link to the first's, a changed one isn't, and a deleted one is gone
- A changed file in the new snapshot leaves the old snapshot's copy untouched
- A run with a partial folder left over picks it up instead of starting again
- A missing drive, a mismatched marker, or a missing or empty source folder fails the run without creating anything
- Folder names can't place anything outside the snapshot, and two similar job names never share a folder

**Done when:** the installed daemon backs up the test server's files to the test drive twice; unchanged files share an inode across the two snapshots (`stat -f %i`) and a changed file doesn't; a snapshot can be browsed in Finder; ejecting the test drive makes the next run fail with nothing written under `/Volumes`; a backed-up file's owner and group show in its extended attributes; and the tests pass.
