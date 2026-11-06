# D1. Servers in Beekeeper

**Phase D — Managing backups in Beekeeper (Mac)** · UI, 1 session

References like §15 point to [00-Info.md](00-Info.md).

Built with you:

- **Servers under each Hive** in the sidebar, with each one's status once D3 adds it. B3 gives each Hive a sidebar section with four pages, which gets long with several Hives: decide here between collapsible sections and one row per Hive with its pages in the detail.
- **Adding a server,** as one flow:
  1. name, host, port and SSH user
  2. Hive's public key, with the `authorized_keys` line ready to copy, and the `from=` restriction offered (§11). C2's restricted line lists every address the Mac has, including ones for virtual machines and OrbStack, so let the person choose which to keep, defaulting to the Tailscale address. The test server sees connections through OrbStack's port forward, so it needs the plain line.
  3. the host key's fingerprint, to check and confirm (§11)
  4. a test connection, with a clear reason when it fails
- **Editing and removing servers.** Changing the host, port or user says it clears the database passwords and needs the host key confirmed again (C1). Removing one asks first, and says its snapshots stay on the drive.
- **Choosing the backup drive** in the Hive's settings (C3), showing each volume's name, format and free space, explaining why only case-sensitive APFS is offered, and warning when the chosen one isn't mounted

**Done when:** in the installed builds, the test server is added through Beekeeper from start to a passing test connection; the test drive is chosen as the backup drive; and ejecting it shows the warning.
