# D2. Editing backup jobs

**Phase D — Managing backups in Beekeeper (Mac)** · UI, 1 session

References like §8 point to [00-Info.md](00-Info.md).

Built with you:

- **A server's backup jobs,** added, renamed and removed. Removing one says its snapshots stay on the drive.
- **The job editor** (§8):
  - directories: the path on the server and its folder name in the snapshot
  - directories can go in nested folders, such as `images/galleries`
  - databases: kind, container service name or host, user, database name, and a password field that says only whether one is set, with Change to replace it (§7)
  - the times it runs
  - its retention tiers
- **The server's quota,** in the server editor, with how much the server uses now
- **Hive's checks** (C1) shown beside the field they're about
- **Lowering the quota or tiers** goes through D4's confirmation once D4 is done

**Done when:** in the installed builds, the test server's directories and all three databases are set up as a job entirely in Beekeeper, and its first scheduled run makes a complete snapshot.
