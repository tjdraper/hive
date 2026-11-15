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
