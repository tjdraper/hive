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

**Decisions (2026-11-06):**

- **rsync 3.5.2,** the latest release, with a fix for a CVE in what a malicious peer can make rsync do. `Scripts/build-rsync.sh` checks the download against a SHA-256 taken from a tarball whose signature verified against the release key rsync.samba.org lists, and builds it for Apple silicon and Intel with extended attributes and none of the optional libraries. It's built into `build/rsync/`, which `build-and-test.sh`, `install-test-build.sh` and the tests use, and the Hive target copies it into `Contents/MacOS` beside the daemon, signed with the hardened runtime, with its license in `Contents/Resources/rsync/`. `ThirdParty/rsync/` holds the license and where the source comes from, for I1. A missing rsync is logged as a fault rather than stopping the daemon, so Beekeeper sees runs fail rather than an offline Hive.
- **rsync's options:** `--archive --delete --fake-super --numeric-ids --secluded-args --stats --timeout=300`, and `--link-dest` when the job's last complete snapshot has that directory's folder. `--numeric-ids` keeps the server's owner IDs instead of mapping them to Mac accounts with the same names. `--secluded-args` passes the path through rsync's protocol rather than the server's shell. On macOS, `--fake-super` keeps owners in the `rsync.%stat` attribute, without Linux's `user.` prefix.
- **`-e`** is `SSHCommand.options` joined with spaces, from `SSHSession.remoteShell()`. rsync splits it on spaces, so a part with anything but plain characters is refused rather than quoted. Each run of rsync, the listing included, gets its own `SSHSession`, since the agent drops Hive's key after two minutes and a long transfer of one directory could outlast that for the next.
- **Missing and empty folders:** before anything is made on the drive, Hive lists the top of each directory with `rsync --list-only`. A missing folder, or a file in its place, fails with exit 23 and `change_dir … No such file or directory` or `Not a directory`; an unreachable server fails with ssh's status 255 and its messages, which C2's reader tells apart. A listing with only `.` is empty. A folder emptied between the listing and its pull is caught by an empty destination afterward.
- **The drive:** `GET /backup-drive` lists the mounted volumes with why Hive can't use each (startup disk, not local, not APFS, not case-sensitive, read-only, another Hive's, a `Hive` folder already in use, or unreadable), and `PUT /backup-drive` with a volume UUID chooses one, audited. Choosing makes `Hive/` and its marker, `.hive-drive.json` with a format and the Hive ID. A run finds the volume by UUID among the mounted volumes, never by path, and needs the marker to match before writing.
- **Snapshots:** `<date-time>` is UTC with no colons, such as `2026-11-06T182353Z`: unambiguous when the clocks go back, sortable, and readable in Finder. A partial is named for when it started, and renamed for when it completed with `RENAME_EXCL`, so it never replaces anything. Server and job folders are `<name> <first 8 hex of the ID>`, with the name kept to letters, digits, spaces, `-` and `_`, and the full ID when the short one is taken. They're stored on `server.snapshotFolder` and `backupJob.snapshotFolder` the first time each is backed up. Every folder Hive makes below `Hive/` is checked to be a real folder, never a link, so nothing written to a snapshot can land outside it.
- **Picking up a partial:** the newest partial in the catalog whose folder still exists is reused, unless it holds a folder the job's directories no longer have, or a link where one of them needs a folder. Those are left for C6 and a new one started.
- **The catalog** is the `snapshot` table: job, server, drive UUID, the three folder names, partial or complete, and when it started and completed, with no foreign keys. A row is added before its folder is made. A partial's manifest is written at the start and after each directory, marked incomplete.
- **Run Now:** `POST /jobs/<id>/run` starts a run and answers 202, or 409 while one is going. `GET /jobs/<id>/run` reads the job's latest run from memory: each directory's time, files and bytes transferred, bytes received, vanished files, and why it failed. Starting a run is audited with the device. The daemon's umask leaves Hive's folders on the drive open only to its user.

**Result (2026-11-06):** the tests pass, running the bundled rsync between temporary folders. Through the Developer window and the development daemon: the test drive was listed as case-sensitive APFS, and the startup disk and the case-insensitive `Promenade` volume with why they can't be used; choosing it wrote the marker; the test server's files were backed up twice, with `change-files` between. In the second snapshot, `photo.jpg`, `foo.jpg` and `.env` shared inodes with the first and the changed `counter.txt` didn't; `Foo.jpg` and `foo.jpg` were both kept; owners showed in `rsync.%stat` (`33:999`, `33:33`, `0:0`); the second run transferred 2 files. Ejecting the drive made the next run fail with `driveMissing` and nothing appeared under `/Volumes`. The system log had each step with its time and sizes, and no paths or hosts.

In the installed builds, through the Developer window: Hive.app's rsync was owned by root and signed with the team's identity and the hardened runtime, and the daemon started with Full Disk Access. The installed Hive's C1 test server got its SSH key, its host key was confirmed, and the drive was chosen. Two runs with `change-files` between gave the same results as above, with owners in `rsync.%stat`, and the second snapshot browsed in Finder. Ejecting the drive failed the next run with `driveMissing`, writing nothing under `/Volumes`. The C1 server's host was `localhost`, which `ssh-keyscan` reported unreachable, since the test server listens only on `127.0.0.1`; with `127.0.0.1` it worked (a follow-up for D1).

**Done when:** the installed daemon backs up the test server's files to the test drive twice; unchanged files share an inode across the two snapshots (`stat -f %i`) and a changed file doesn't; a snapshot can be browsed in Finder; ejecting the test drive makes the next run fail with nothing written under `/Volumes`; a backed-up file's owner and group show in its extended attributes; and the tests pass.
