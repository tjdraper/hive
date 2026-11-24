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

## Session 1

Done: everything above. `Scripts/build-and-test.sh` passes, and everything in "done when" is true.

What was decided along the way:

- **A server's metrics are `server.hasMetrics`,** apart from its Scout. Enrolling sets it; Remove Metrics clears it and deletes the Scout. A recovery file keeps it (`hasMetrics`, optional, so older files still restore) and never the Scout, so a restored server has metrics and no Scout, which Beekeeper shows as needing to enroll again. Regenerate Identity now deletes every Scout, since each pinned the old key, and keeps `hasMetrics`, so it ends in the same state. The migration gives metrics to each server that had a Scout.
- **`GET /servers/:id/metrics`** answers `ServerMetricsState` (HiveKit): `hasMetrics`, and the Scout's enrolment, last seen, last report, version, platform, distribution, kernel, clock offset, hidden processes, last refusal and `update`. What the metrics database holds from before the Scout enrolled isn't shown as its. `DELETE` on the same path replaces A2's `DELETE /servers/:id/scout` and is recorded as `ScoutChange.removed`, now summarised as removing metrics.
- **Out of date** is `ScoutUpdate.newerRelease` when `Hive.app`'s `ScoutVersion` (now also in the daemon's Info.plist) is newer than the Scout's version, compared as three numbers, or `protocolNotAccepted` when the protocol version it last signed in with isn't accepted. A Scout's sign-in now records its protocol version before refusing an old one, so it shows. Hive's own version plays no part.
- **The command** is `ScoutCommand` in HiveKit, built from `ScoutRelease`, which reads Beekeeper's own Info.plist and refuses any value that isn't what a release writes. The code must be `scout1:` and base64url within a code's length, and a `--ssh-user` name POSIX's portable pattern of at most 32 characters; anything else gives no command. It downloads with `curl`, or `wget` where there's no `curl`, into a `mktemp -d` folder, checks `sha256sum -c` under `set -e`, and pipes the code into `./hive-scout install`. Checked by hand in the Debian test VM under bash and dash, with the development binary: a matching hash runs it, a wrong one stops before it, and the folder is removed either way. BusyBox `sh` on Alpine parses it, but it wasn't run there. `ScoutCommand.update` is the same with `< /dev/null`, which keeps the enrollment (A4).
- **A development build has no download address,** so the Add Metrics sheet shows the code itself for `Scripts/scout-test-vm.sh install`, which copies the development binary in instead.
- **Beekeeper:** a Metrics section on every server's page (`ServerMetrics/`): Add Metrics, or the state with Enroll Scout Again and Remove Metrics; the update command when out of date; the uninstall command once removed; and, for a server with metrics and no Scout, that it has to enroll again. The Add Metrics sheet opens a confirmed enrollment window, shows the command for each CPU, the first being the one the last Scout reported, with the time left, and notices the Scout enrolling. Closing it closes the window. The section refreshes every 15 seconds.
- **Scout's migrations moved** to `Scouts/ScoutSchema.swift` unchanged, and the recovery workflows to `Recovery/RecoveryWorkflows.swift`, to stay within SwiftLint's file and type lengths.

Checked on Ivy with the development daemon (2026-11-23): the store migrated, and the two test servers with Scouts kept their metrics; the Metrics section showed A2's Scout as reported (0.1.1, linux-aarch64, Debian 12, kernel, clock in step); Add Metrics opened its sheet and asked for confirmation, and cancelling it closed the sheet; Remove Metrics on "Test: A4 Alpine" revoked its Scout, recorded it in the audit log, and showed the uninstall command.

Checked in installed builds (2026-11-24), with `Scripts/install-test-build.sh --mac-installed` over the installed Hive, a release from before Scout: its store migrated through A2 to B2 with its servers and jobs intact. Added "B2 Test VM" by name only; Add Metrics asked for Touch ID and showed the code, which this build, having no download address, shows instead of the command; `Scripts/scout-test-vm.sh install` in the Debian VM enrolled with it through 10.0.0.9:4483, the sheet said so, and the server's page showed the Scout reporting (0.1.0, linux-aarch64, Debian 12, clock in step). Remove Metrics stopped it at once: Hive logged the Scout's next sign-in as refused, the Scout logged "Refused by Hive" and kept its samples, no more were kept, and the audit log has the server added, the window opened, the Scout enrolled and its metrics removed. The test server was removed afterwards; the Debian VM's Scout is still installed, refused, until it enrolls again.

Follow-ups:

- **The pasted command itself** hasn't run end to end from a download, since only a release has a download address. Its steps ran in the Debian VM with the development binary, and C4 runs it for real on the first release with Scout.
