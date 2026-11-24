# B1. Servers without SSH details

**Phase B — Metrics in Beekeeper** · Mixed, 1–2 sessions

References like §7 point to [00-Info.md](00-Info.md).

A server added only for metrics has no SSH details (§7). Today `Server.connection` is required in HiveKit and everything that reads a server assumes it.

## Engine

- **SSH details become optional:** host, port, user, host key and SSH key, needed only once a server has a backup job. Adding a first job asks for them, with the host key confirmation as today.
- **Everything that reads them** handles a server without: backup runs, the job queue, rotating keys, host key alerts, recovery files and the confirmation that changing a server's host, port or SSH user needs today (§12)
- **Recovery files** written before this change still restore, and ones written after it restore on this version
- **The API version goes up,** since older Beekeepers would misread a server without SSH details.

## UI

Built with you:

- **Add Server** that can stop at a name
- **A server's page** without SSH details: no backup sections until they're added, and a way to add them

## Tests

- A server without SSH details can't get a backup job until it has them
- Recovery files from before and after the change restore
- Each place that reads SSH details skips or refuses a server without them, as it should

**Done when:** you can add a server by name only, then add SSH details and a backup job to it, and back it up from the test server; and the tests pass.

## Session 1

Done: servers can be added by name only, and get their SSH details later through the same steps as Add Server. `Scripts/build-and-test.sh` passes, and everything in "done when" is true.

What was decided along the way:

- **A server's SSH details are host, port and user, all three or none,** stored as optional columns with a check that they go together. SQLite can't relax `NOT NULL` in place, so the migration remakes the `server` table, keeping every row. `Server.connection` and `ServerDraft.connection` are optional in HiveKit, and the API version is 3, with 3 the oldest compatible.
- **Hive's SSH key is made with a server's first SSH details,** whether it's added with them or given them later, so a server without them has no key. Giving a server its first details needs no confirmation: nothing is replaced, and it has no jobs with passwords to send anywhere. Changing them afterwards needs it, as before. The audit log records "Added SSH details to …".
- **SSH details can't be taken away** once a server has them, so a server with jobs always has them. Hive refuses a draft without them with `ConfigurationProblem(field: .connection, reason: .missing)`, the same refusal as a job for a server without them, or a new SSH key for one.
- **What refuses or skips a server without SSH details:** adding a job and making a new SSH key refuse it (422); host key scans and connection tests answer the new `ConnectionFailure.noSSHDetails` without running `ssh`; loading an SSH target, so the job queue too, answers `noSSHDetails` (with `BackupFailure.noSSHDetails` beside it), though no job can reach it; key rotation leaves such servers out; host key alerts scan only a server with details.
- **Recovery files** keep `currentFormat` 1. `host`, `port` and `user` are optional in `RecoveryContents.Server`, so files from before still restore, and a file with a server without them restores on this version, not an older one.
- **Beekeeper:** Add Server has a "Connect over SSH" switch; off, it adds the server by its name and closes. A server without SSH details has a page with only an "Add SSH Details…" button, which, like "Add Job…" for such a server from anywhere, opens the Add Server steps for that server: details, Hive's key, host key, test. Its Edit sheet has only its name. The sidebar shows no badge for it, and the Overview "No SSH details".

Checked (2026-11-23), on Ivy with the development daemon and the test server:

- Added "Metrics Box" by name only; its page offered only Add SSH Details. Gave it 127.0.0.1:2222 as root, authorized Hive's key, confirmed the host key the test server showed (SHA256:fxDw67…PPrc) and the connection test passed. Added a job for `/srv/sites/example`, ran it, and it made a 324 kB snapshot on the test drive.
- The development store migrated with its existing servers, keys and Scouts intact, and a Beekeeper still on API version 2 was refused sign-in until it was updated.

Follow-ups:

- **Adding SSH details from "Add Job…"** ends on the server's page rather than going on to the job editor, since SwiftUI can't present the second sheet while the first is closing. The page's "Add Job…" is then one click away.
