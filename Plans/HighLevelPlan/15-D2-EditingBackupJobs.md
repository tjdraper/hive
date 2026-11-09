# D2. Editing backup jobs

**Phase D — Managing backups in Beekeeper (Mac)** · UI, 1 session

References like §8 point to [00-Info.md](00-Info.md).

Built with you:

- **A server's backup jobs,** added, renamed and removed. Removing one says its snapshots stay on the drive.
- **The job editor** (§8):
  - directories: the path on the server and its folder name in the snapshot
  - directories can go in nested folders, such as `images/galleries`
  - databases: kind, container service name or host, user, database name, and a password field that says only whether one is set, with Change to replace it (§7)
  - the times it runs, as many a day as you like, with a new job starting at midnight
  - its retention tiers
- **The server's quota,** in the server editor, with how much the server uses now
- **Hive's checks** (C1) shown beside the field they're about: a 422 lists every problem with its field, its place in a list and a reason, never the value
- **Lowering the quota or tiers** goes through D4's confirmation once D4 is done

- **From C6:** a new job starts with `RetentionTiers.suggested`, 30 daily and 12 monthly, and a new server with no quota.
- **From C4:** the official Postgres image trusts every connection from `127.0.0.1` by default, so a wrong password there still dumps. Say so beside a Postgres database's password, so nobody takes a working dump as proof the password is right.

- **From D1:** a server's jobs can nest under it in the sidebar, which already nests servers under each Hive, and the toolbar path (`LocationPath`) takes a third part. `EditServerSheet` sends the server's quota back unchanged; the quota field goes there.

**Decisions (2026-11-09):**

- **Jobs nest under their server** in the sidebar, open until closed, and a server with none has no disclosure triangle. Collapsing a server with one of its jobs selected selects the server. The toolbar path reads Hive › Server › Job. A server's right-click menu adds a job; a job's edits or removes it.
- **A job's page** shows its configuration, with Edit… and Remove… in the toolbar, and D3 adds its status and snapshots. The server page lists its jobs first, with Add Job… as a row of the list rather than in the section header, where it didn't read as a button.
- **One sheet adds and edits a job,** with sections for its name, directories, databases, the times it runs and what it keeps. A directory's folder follows the last part of its path until it's named something else. Each database has a section of its own. A saved password shows only "Set", with Change… and Keep Current. Times are shown in GMT so the picker never shifts them: they're the Hive Mac's local times, whatever the time zone where Beekeeper runs. Hive's problems show under the field and row they name, and adding or removing a row clears them, since they name rows by their place in the list.
- **The quota** is in the server editor, as a switch and an amount in GB or TB. Turning it on suggests the saved quota or twice what the server uses now, at least 100 GB. `GET /servers/<id>/space` gives the server's total on the chosen drive, measured the way the quota is. Lowering the quota or a tier shows a warning until D4's confirmation replaces it.
- **The test databases have names of their own**, since Hive refuses two databases with the same name in one job (each names its dump): `site` in the MariaDB container, `shop` in MySQL, `blog` in Postgres and `notes` in the server's own MariaDB, all for user `site`.

- **A job's next run is worked out when its times are saved,** in the same transaction. The scheduler only did it at its next check, up to 30 seconds later, so a time set a minute ahead in the installed build was put off a day.

**Result (2026-11-09):** the tests pass. In the installed builds, the test server's three directories, one nested, and all four databases were set up as one job in Beekeeper, and its scheduled run made a complete snapshot, picking up the partial one a first run left when a database user was mistyped. Each dump restored into a new container and matched its source.

**Done when:** in the installed builds, the test server's directories and all three databases are set up as a job entirely in Beekeeper, and its first scheduled run makes a complete snapshot.
