# B2. Adding metrics to a server

**Phase B — Metrics in Beekeeper** · Mixed, 1 session, installed build

References like §2 point to [00-Info.md](00-Info.md).

The pasted-command way, for every server. B3 adds installing from Beekeeper where Hive has SSH access.

## Engine

- **A server's metrics state through the API:** whether it has a Scout, enrolled when, last seen, its version, distribution, kernel and clock offset, whether processes are hidden, and whether it's out of date: its version older than the Scout `Hive.app` carries, or its protocol no longer accepted (§2).
- **Recovery files** keep, for each server, that it had metrics and its alert limits once C1 adds them, but never a Scout's key. After a restore, Hive knows which servers need their Scout enrolled again.

## Beekeeper

- **The pasted command, built by Beekeeper** (§2): the download address, version and hashes built into Beekeeper (A5), and the enrollment code from Hive, checked as base64url within its expected length, passed on standard input. `--ssh-user` only when B3 needs it, with the name checked against POSIX's portable pattern. Anything that fails a check stops with an error instead of a command.

## UI

Built with you:

- **Add Metrics** on a server, with confirmation, showing the command for x86_64 and aarch64 with the time left on its code, and noticing when the Scout enrolls
- **The server's metrics state,** an out-of-date Scout with the command to update it, and **Remove Metrics** with the command to uninstall
- **After a restore or a new identity,** each server that had metrics says its Scout has to enroll again, with the command

## Tests

- A code or user name holding anything outside its pattern, such as `$(`, a quote, a space or a newline, gives no command
- A Scout is out of date by version or protocol, and not when only Hive changed
- Removing metrics revokes the Scout, and the audit log records it
- After restoring a recovery file, servers that had metrics say so

**Done when:** in installed builds, you add a server by name only, add metrics to it, run the command in the test VM, and Beekeeper shows it reporting; removing metrics stops it being accepted; and the tests pass.
