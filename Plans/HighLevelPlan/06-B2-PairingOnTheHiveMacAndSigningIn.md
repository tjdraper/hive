# B2. Pairing on the Hive Mac and signing in

**Phase B — Connecting Beekeeper on the Mac** · Engine, 1–2 sessions, installed build

References like §6 point to [00-Info.md](00-Info.md). Read the brainstorm's "Authentication: a key per device, with no passwords".

- **Hive's store starts here** (§3): GRDB with migrations, holding the Hive ID, created once, and the paired devices.
- **The XPC pairing service** on the daemon's Mach service. Hive requires the caller to be signed with its own team ID and to have Beekeeper's bundle ID, checked from the audit token through the connection's code signing requirement. Nothing team-specific is hard-coded. The development daemon's Mach service is `<prefix>.Hive.Debug.Pairing` (A2), so a Debug Beekeeper pairs with it, not with an installed Hive.
- **Decide whether Debug Beekeeper gets its own bundle ID,** as Debug Hive did in A2 (`<prefix>.Hive.Debug`). Sharing the installed Beekeeper's lets TCC and anything keyed by bundle ID treat the two as one app: in A2, starting the Debug Hive reset the installed Hive's Full Disk Access.
- **Pairing over XPC:** Beekeeper creates a Secure Enclave key for this Hive and sends its public key and device name. Hive records the device and answers with its Hive ID, key hash and port. The messages are HiveKit types.
- **Where Beekeeper keeps its keys** (§19): a Secure Enclave key's `dataRepresentation` works for any program on the Mac, so a file readable by your user isn't enough. Keep it in the keychain, limited to Beekeeper's access group, or somewhere equally out of other programs' reach. Record the decision in §3.
- **Signing in** (§6): a challenge with a nonce and an expiry, signed by the device's key, and answered with a short-lived session token. The token works for HTTP requests and the WebSocket. A device signs in again when it expires.
- **The gate** (B1) lets the challenge and pairing endpoints through unauthenticated, beside the health check, and checks the session token on everything else.
- **An API version** exchanged at sign-in, so a Beekeeper and a Hive that can't work together say which one to update instead of failing in odd ways
- **Rate limiting and lockout** for failed sign-ins, per address and per device (§5)
- **Beekeeper on the Mac,** for now: a button to pair with this Mac's Hive and a line showing that it's signed in. B3 builds the real window.
- **Logging:** pairing and sign-in results and why one was refused. Never device names, tokens or keys.

## Tests

- A valid signature signs in, and a replayed, expired or reused one doesn't
- A revoked device's key can't sign in
- Repeated failures from one address lock out that address and not others, and the lockout ends
- A session token stops working when it expires

**Decisions (2026-11-05):**

- **Debug Beekeeper's bundle ID** is `<prefix>.HiveBeekeeper.Debug` (§3). The project sets `HIVE_BUNDLE_ID` and `BEEKEEPER_BUNDLE_ID` per configuration, and the build writes the Mach service and the other side's signing identifier into the daemon's and Beekeeper's Info.plist (`Configuration/HiveDaemon-Info.plist`, `Configuration/Beekeeper-Info.plist`).
- **Beekeeper's keys** are in the keychain under its own access group (§3). Its Mac builds now need a provisioning profile, which Xcode makes, so the build scripts pass `-allowProvisioningUpdates`.
- **The XPC check** runs on each message's sender with `senderSatisfies(.isFromSameTeam(andMatchesSigningIdentifier:))`, so a refusal is logged and answered. Beekeeper requires the same of the daemon, since any program running as you can register a Mach service of the same name for your login session.
- **Sign-in:** `POST /sign-in/challenge` gives a challenge that Hive recognizes by a MAC under a key made at start, so issuing one stores nothing. `POST /sign-in` takes the device ID, the challenge, a signature over "Hive sign-in v1", the Hive ID, the device ID and the challenge, and the API versions. A challenge lasts 60 seconds and is used once, sessions last 15 minutes and are kept in memory only, and the token is sent as `Authorization: Bearer`. A refused sign-in gets 401 with no reason, a lockout 429, and an incompatible API version 409 naming the app to update.
- **Lockout:** 5 failures within 15 minutes lock out the address, or a paired device, for 15 minutes. IPv6 addresses count by their /64, and IPv4 addresses arriving as `::ffff:a.b.c.d` by their IPv4 address.
- **The pairing endpoint** is left to G1. Until a pairing window exists it would only ever refuse, so the gate lets through just the health check and the two sign-in routes.
- **Until B3's store,** Beekeeper keeps the pairing only while it runs. Pressing Pair again after a relaunch pairs a new device.

**Result (2026-11-05):** in the Debug build, Beekeeper paired with the development daemon over XPC with no code, kept its key in the keychain, and signed in over HTTPS on `127.0.0.1:4484`. A program signed by the same team with another identifier, and an ad hoc one claiming Debug Beekeeper's identifier, were both refused (`notBeekeeper`). A team-signed program without the entitlement got `errSecMissingEntitlement` for Beekeeper's access group, and team-signed and ad hoc programs claiming the group were killed by macOS at launch. A Developer ID export of Beekeeper got its provisioning profile automatically. In the installed build, the same held: Beekeeper paired with the installed Hive with no code and signed in on `127.0.0.1:4483`. A team-signed program with another identifier, which stands in for a Beekeeper built with a different bundle ID, and an ad hoc one claiming Beekeeper's identifier, were refused. Beekeeper's access group gave `errSecMissingEntitlement` to a program without the entitlement, and programs claiming it were killed at launch. The installed Beekeeper has no `get-task-allow`, so no debugger can attach to it.

**Done when:** the installed Beekeeper pairs with the installed Hive with no code, and signs in over HTTPS on `127.0.0.1`; a Beekeeper built with a different bundle ID fails the XPC check; another program running as you can't use Beekeeper's key; and the tests pass.
