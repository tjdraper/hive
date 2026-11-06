# C1. Servers and backup jobs

**Phase C — Backups in Hive** · Engine, 1 session

References like §8 point to [00-Info.md](00-Info.md). Look at `../site-backups/src/Backup/Config` and `../site-backups/config/Dependencies/BackupConfigBindings.php` for what the PHP version stores.

- **The configuration in Hive's store** (§8): servers, backup jobs, their directories, databases and times, retention tiers and server quotas, with migrations from B2's schema.
- **Secrets stored encrypted** (A4). Database passwords are the first.
- **The API,** with HiveKit types, to list, add, change and remove each of them. Secrets are write-only: a response says whether one is set, never what it is (§7).
- **Checks before saving,** with messages Beekeeper can show: absolute paths on the server; folder names that are unique in the job, relative, and free of `..` and empty parts, so `images/galleries` is fine; valid times; sensible tiers and quotas.
- **Changing a server's host, port or SSH user** clears its jobs' database passwords and its confirmed host key, so both are entered and confirmed again (§7). D4 adds the confirmation.
- **Lowering a quota or a job's tiers** is marked as needing confirmation, for D4 to enforce (§10)
- **Removing a server or job removes its configuration only.** Its snapshots stay on the drive, and deleting them is D4's confirmed action.
- **The audit log** gets an entry for every change: what changed and which device changed it, never a secret's value.

## Tests

- Each kind can be added, changed and removed through the routes
- No route ever returns a secret, including in errors
- Bad paths, folder names, times, tiers and quotas are refused with a reason
- Changing a server's host, port or user clears its database passwords and host key
- Every change writes an audit log entry, and none holds a secret

**Decisions (2026-11-06):**

- **The routes:** `GET`/`POST /servers`, and `GET`/`PUT`/`DELETE /servers/<id>`. `GET /jobs` lists every server's jobs, `GET`/`POST /servers/<id>/jobs` lists or adds one server's, and `GET`/`PUT`/`DELETE /jobs/<id>` reads, changes or removes one. A server or job is sent whole, as a `ServerDraft` or `BackupJobDraft`, like the settings. Adding answers 201, removing 204, an unknown ID 404, and a refusal 422 with every problem found.
- **Refusals** list each problem as a field, its place in the list for a directory, database or time, and a reason. They never repeat what was sent, so a password can't come back in one.
- **The store:** `server`, `backupJob`, and tables for a job's directories, databases and times, kept in the order sent. Removing a server removes its jobs, and removing a job removes its parts, through foreign keys. Server names are unique, and job names unique on their server, ignoring case.
- **Database passwords** are sealed (A4) in their database's row. A draft's database carries its ID and either a new password or none, which keeps the one it has. Only an ID the job already has carries a password over, so one can't be moved to a database on another server. A response says only `hasPassword`.
- **Checks:** a host is ASCII letters, digits, `-`, `.`, `_` and `:`, lowercased, and a user ASCII letters, digits, `-`, `.` and `_`; neither may start with `-`, which `ssh` would read as an option. Paths lose trailing slashes. A folder can't be inside another of the job's folders, since backing up the outer one would delete what the inner one put there. Database names, users and service names are kept to plain characters, a database's name is unique in its job since it names the dump, and a password can't hold control characters. A job needs at least one time, and a directory or database. Tiers are 1–3650 daily and 0–1200 monthly snapshots. A quota is bytes, or none for no limit.
- **Needing confirmation:** `ConfirmationRequirement` names why a change would need the `.userPresence` key: a changed connection, a lower quota or tier, or a password replaced. A password entered where there was none needs nothing. For now Hive only logs the reasons; D4 enforces them.
- **The audit log** has a server entry and a job entry, each with a change: added, renamed, connection, quota or removed for a server, and added, renamed, directories, databases, password entered, times, retention or removed for a job. Removing a server records each of its jobs too.

**Result (2026-11-06):** the tests pass. In the installed builds, the store migrated from B3's with the Hive ID and devices kept, and Beekeeper signed in as before. A server and a job with two directories and a database with a password, added through the Developer window, came back as saved from `GET /servers` and `GET /jobs`, the job's database showing only `hasPassword`. The Developer window sent its body with a GET, which `URLSession` refuses before sending, and Beekeeper showed that as the Hive being offline; it now sends a body only with POST and PUT.

**Done when:** the tests pass; the installed daemon migrates its store from B2's schema without losing the Hive ID or devices; and a server and job created through the Developer window (B3) come back as saved.
