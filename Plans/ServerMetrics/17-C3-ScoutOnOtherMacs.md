# C3. Scout on other Macs

**Phase C — Alerts, Macs and release** · Engine, 1–2 sessions, installed build, needs you

References like §4 point to [00-Info.md](00-Info.md).

For Macs other than the Hive's, which reports itself (C2). Uses C2's macOS readers.

- **Which user it runs as:** depends on what C2 found an unprivileged process can see of other users' processes. Decide between a root daemon with nothing else to it and an unprivileged one that sees what Hive can, and record why.
- **`sudo hive-scout install`** writes a LaunchDaemon in `/Library/LaunchDaemons` and its state in `/Library/Application Support/Hive Scout/`, with A4's rules for the code and the state folder.
- **A universal binary,** signed with Developer ID and notarized by the release script, attached to the release beside the Linux ones, with its statement signed as in A5. A bare binary can be notarized but not stapled; a `curl` download isn't quarantined, so the Developer ID signature is what matters.
- **Installing from Beekeeper** (B3) works over SSH where the Mac has Remote Login on.

**Done when:** an installed Scout on a second Mac (Ivy) reports to the installed Hive, survives a restart, measures within §3's budget, updates through `manage`, and uninstalls cleanly; and the tests pass.
