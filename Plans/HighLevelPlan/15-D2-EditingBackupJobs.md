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

**Done when:** in the installed builds, the test server's directories and all three databases are set up as a job entirely in Beekeeper, and its first scheduled run makes a complete snapshot.
