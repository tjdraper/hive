# A2. Enrolling a Scout

**Phase A — Scout** · Engine, 1–2 sessions

References like §2 point to [00-Info.md](00-Info.md). Read §12 on pairing, signing in and confirmation, and the code it names, which this follows.

## Hive

- **Scouts in the store:** for each, the server it reports for, its public key, when it enrolled, when it was last seen, and the version and system it last reported. At most one for each server; enrolling again replaces the last.
- **Enrollment windows** (§2) in a store of their own, not `PairingWindowStore`, which holds one window and closes it when another opens: one window for each server, several open at once, none touching a device's pairing window. Opened through a confirmed route with a new `ConfirmationReason`, single-use, 15 minutes, all closed when Hive restarts. Refused while there are no address options. Opening, closing and using one go in the audit log.
- **The code** is `scout1:` and base64url of the version, the Hive ID, the server ID, the pin, a 128-bit token and the addresses with their ports, like `PairingCode`.
- **The pairing endpoint takes a Scout's token too,** so the open routes in `RequestGate` don't change. A token says which kind of window it belongs to, and a device's token can't enroll a Scout or the other way round. Refusals count toward the pairing endpoint's existing per-address lockout.
- **Signing in** uses the existing challenge and sign-in routes. A session records whether it belongs to a device or a Scout, and which server a Scout's is for. `RequestGate` sends a Scout's session only to Scout's routes, and a device's never to them.
- **Revoking:** removing a server's Scout deletes its key and ends its sessions.
- **AGENTS.md's security rules** gain two: Scout never listens on a port or acts on anything Hive sends over its connection, and a Scout's session reaches only Scout's routes, for its own server.

## Scout

- **`hive-scout enroll`** reads the code from standard input, never from its arguments (§2). It makes a P-256 key, connects to the code's addresses in turn with the connection A1 chose, refuses any key but the pinned one, enrolls, and saves its key, the Hive ID, the pin, the server ID and the addresses to a `0600` file in its state folder. Enrolling with a key already saved replaces it, so a server can move to another Hive or enroll again after a restore.
- **A running Scout picks up a new enrollment** when told to reload (A4), and connects at once, keeping its buffer.
- **Signing in** with the saved key, and again before the session runs out.

## Tests

- A Scout's token works once, for its own server, and never after it expires or the window closes
- Two servers' windows open at once both work, and neither closes a device's pairing window
- A device's token can't enroll a Scout, and a Scout's can't pair a device
- Opening a window without confirmation is refused
- A Scout's session is refused on every device route, and a device's on every Scout route
- A revoked Scout can't sign in, and its open session ends
- Scout refuses a Hive showing another key, and an expired or used code

**Done when:** with a code opened from Beekeeper's Developer window, `hive-scout enroll` in the test VM reaches the development Hive at the Mac's address, enrolls, and signs in; the window and the enrollment show in the audit log; and the tests pass.

## Session 1

Done: everything above. `Scripts/build-and-test.sh` passes.

Checked end to end (2026-11-21): with a code opened from Beekeeper's Developer window, `hive-scout enroll` as `hive-scout` in the test VM reached the development Hive at `host.orb.internal:4484`, enrolled and signed in. Its key file is `0600` and owned by `hive-scout`. Hive recorded the Scout with its version and platform (`0.1.0`, `linux-aarch64`), and the audit log has the window opening and the Scout enrolling. The same code used again was refused, and Hive logged it as no window open.

What was decided along the way:

- **Scout's wire types are in `ScoutProtocol`,** which HiveCore now depends on by path: `EnrollmentCode`, the enrollment and sign-in messages, `ScoutEndpoint` and `ScoutProtocolVersion` (1; Hive accepts it and the one before). Beekeeper's side, the window and the audit events, is in HiveKit.
- **Devices and Scouts share the open routes,** and Hive tells them apart by what the body holds: a Scout's enrollment sends `scoutPublicKey` and its sign-in `scoutID`. A token opens only its own kind of window, so a device's token sent as a Scout's is a wrong token, and the other way round. Scouts share the pairing lockout, and the sign-in challenges and lockouts. A Scout signs a statement with a label of its own, so a device's signature never signs a Scout in.
- **The gate matches a Scout's routes exactly,** like the open routes (`RequestGate.scoutRoutes`, only `GET /scout/session` for now), since several device routes, such as `GET /servers`, don't check the device themselves. A device's session is refused on any path whose first part is `scout`. Both refusals answer 403.
- **Audit events are `AuditEvent.scout`** with a `ScoutChange`: window opened, closed, a Scout enrolled (and whether it replaced one), and removed. Enrolling is recorded as made by the device that opened the window, which has to still be paired.
- **`DELETE /servers/:id/scout`** removes a server's Scout and ends its sessions, for B2's Remove Metrics. Removing the server removes its Scout with it.
- **Scouts stay in the store after Regenerate Identity,** so B2 can say which servers need to enroll again. Their Scouts refuse the new key by its pin.
- **Scout keeps its enrollment in `enrollment.json`** in its state folder, `/var/lib/hive-scout` unless `--state-directory` gives another, `0600`, written beside it and renamed into place, never through a symbolic link. Enrolling checks the folder can be written before it uses up the code.
- **`ScoutSessionKeeper`** signs in again a minute before a session runs out. A3's `run` uses it.
- **Beekeeper's Developer window** sends through the confirmation workflow, asking for Touch ID when Hive answers 428, so it can open enrollment windows.
- **Left for A4:** a running Scout reloading its enrollment on SIGHUP, since `run` doesn't exist until A3.
