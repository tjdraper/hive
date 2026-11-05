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

**Done when:** the tests pass; the installed daemon migrates its store from B2's schema without losing the Hive ID or devices; and a server and job created through the Developer window (B3) come back as saved.
