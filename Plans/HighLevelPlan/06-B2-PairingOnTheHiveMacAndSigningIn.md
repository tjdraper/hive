# B2. Pairing on the Hive Mac and signing in

**Phase B — Connecting Beekeeper on the Mac** · Engine, 1–2 sessions, installed build

References like §6 point to [00-Info.md](00-Info.md). Read the brainstorm's "Authentication: a key per device, with no passwords".

- **Hive's store starts here** (§3): GRDB with migrations, holding the Hive ID, created once, and the paired devices.
- **The XPC pairing service** on the daemon's Mach service. Hive requires the caller to be signed with its own team ID and to have Beekeeper's bundle ID, checked from the audit token through the connection's code signing requirement. Nothing team-specific is hard-coded. The development daemon's Mach service is `<prefix>.Hive.Debug.Pairing` (A2), so a Debug Beekeeper pairs with it, not with an installed Hive.
- **Decide whether Debug Beekeeper gets its own bundle ID,** as Debug Hive did in A2 (`<prefix>.Hive.Debug`). Sharing the installed Beekeeper's lets TCC and anything keyed by bundle ID treat the two as one app: in A2, starting the Debug Hive reset the installed Hive's Full Disk Access.
- **Pairing over XPC:** Beekeeper creates a Secure Enclave key for this Hive and sends its public key and device name. Hive records the device and answers with its Hive ID, key hash and port. The messages are HiveKit types.
- **Where Beekeeper keeps its keys** (§19): a Secure Enclave key's `dataRepresentation` works for any program on the Mac, so a file readable by your user isn't enough. Keep it in the keychain, limited to Beekeeper's access group, or somewhere equally out of other programs' reach. Record the decision in §3.
- **Signing in** (§6): a challenge with a nonce and an expiry, signed by the device's key, and answered with a short-lived session token. The token works for HTTP requests and the WebSocket. A device signs in again when it expires.
- **An API version** exchanged at sign-in, so a Beekeeper and a Hive that can't work together say which one to update instead of failing in odd ways
- **Rate limiting and lockout** for failed sign-ins, per address and per device (§5)
- **Beekeeper on the Mac,** for now: a button to pair with this Mac's Hive and a line showing that it's signed in. B3 builds the real window.
- **Logging:** pairing and sign-in results and why one was refused. Never device names, tokens or keys.

## Tests

- A valid signature signs in, and a replayed, expired or reused one doesn't
- A revoked device's key can't sign in
- Repeated failures from one address lock out that address and not others, and the lockout ends
- A session token stops working when it expires

**Done when:** the installed Beekeeper pairs with the installed Hive with no code, and signs in over HTTPS on `127.0.0.1`; a Beekeeper built with a different bundle ID fails the XPC check; another program running as you can't use Beekeeper's key; and the tests pass.
