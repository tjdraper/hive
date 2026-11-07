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
- **From C3:** a host of `localhost` failed the host key scan as unreachable against the test server, which listens only on `127.0.0.1`, while `127.0.0.1` worked. Check whether `ssh-keyscan` tries only the first address, and either try each or say so when adding a server.
- **Choosing the backup drive** in the Hive's settings (C3), showing each volume's name, format and free space, explaining why only case-sensitive APFS is offered, and warning when the chosen one isn't mounted

**Decisions (2026-11-07):**

- **The sidebar** has one row per Hive with its servers nested under it, rather than a section per Hive. Selecting the Hive shows its pages (Overview, Devices, Audit Log, Settings), switched with a segmented control in the toolbar. A server not set up yet, with no confirmed host key or no SSH key, has an orange mark until D3 adds status. Collapsing a Hive with one of its servers selected selects the Hive, as Finder does, and a path in the toolbar, like Xcode's jump bar, says which Hive a server is on.
- **Adding a server** is a sheet with four steps: connection, Hive's key, host key, test. The server is saved after the first, so closing the sheet later leaves it listed as not set up, and its page has the same three checks to carry on from.
- **The `from=` restriction:** `ServerSSHKey` now carries the key, the comment and the Hive Mac's addresses with their interfaces, and `authorizedKeysLine(acceptingFrom:)` builds the line, so Beekeeper offers each address. "Only from these addresses of the Hive's Mac" starts with the Tailscale ones (100.64.0.0/10 and fd7a:115c:a1e0::/48) ticked; "From any address" gives the plain line, which the test server needs.
- **Editing and removing** are in the server page's toolbar and the sidebar's right-click menu. Changing the host, port or user warns that it clears the jobs' database passwords and the host key.
- **`localhost`:** `ssh-keyscan` connects only to the first address a name resolves to, unlike `ssh`, and `localhost` gives `::1` first. Hive resolves the name itself and scans up to four addresses in turn, reporting a server that answered without a usable key over addresses that didn't answer.
- **The backup drive** is the first section of the Hive's settings, with a chooser listing each volume's format and free space and why Hive can't use the others. The Overview warns when no drive is chosen or the chosen one is missing or unusable, checking every 15 seconds.
- **An offline Hive** is asked again after 1 second, then 2, 4, 8 and 16, then every 30, so Beekeeper connects as soon as a restarted daemon is listening.

**Result (2026-11-07):** the tests pass. In the installed builds, the test server was added through Beekeeper from start to a passing test connection, the test drive was chosen as the backup drive, and ejecting it showed the warning in the Overview and Settings, which cleared once it was mounted again.

**Done when:** in the installed builds, the test server is added through Beekeeper from start to a passing test connection; the test drive is chosen as the backup drive; and ejecting it shows the warning.
