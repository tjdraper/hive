# G1. Pairing more devices

**Phase G — Replacing site-backups** · Mixed, 1–2 sessions, installed build, needs you

References like §6 point to [00-Info.md](00-Info.md). Read the brainstorm's "Authentication: a key per device, with no passwords".

Before the move off site-backups, so the real Hive can be managed from your everyday Mac, not just the Hive Mac.

## Engine

- **Address options:** the addresses a device can reach the Hive at, such as its LAN address, its MagicDNS name and a public hostname. Hive suggests the ones it can find, and you edit the list in its settings.
- **The pairing window** (§6), opened by a paired Beekeeper with confirmation, since a new device gets full access: a single-use token that expires in about 5 minutes, and a payload with the Hive ID, the address options, the key hash and the token
- **The pairing endpoint** answers only while a window is open. It takes the token, the new device's public key and its name, and closes the window once used. Failed attempts are rate limited and lock out, per address (§5).
- **Several Hives:** a device pairing with a second Hive creates a separate key for it (§6)

## UI

Built with you:

- **Pair a Device** in the Hive's settings, showing the QR code and a pairing code to copy, with the time left. The code is long because it carries the key hash. Making it short enough to type would mean trusting the network for the key (§5).
- **Add a Hive** in Beekeeper, by pasting a pairing code. H2 adds scanning the QR code.
- **Connecting to whichever address answers,** trying them in order
- **A port changed from another device:** B3's Beekeeper updates its saved port only for changes it makes itself, so every other device loses the Hive until its port is fixed. Address options should carry the port, and Beekeeper should pick up a new one.

## Tests

- A token works once, never after it expires, and never while no window is open
- Opening a window without confirmation is refused
- A pairing code with a wrong key hash fails to connect
- Repeated wrong tokens lock out that address

- **From D4:** a confirmed route reads its request with `ConfirmedRequest.read` and checks `ConfirmationRequirement.check` inside the store's write transaction, against the stored values. Add the new `ConfirmationReason` to HiveKit, its Touch ID wording to `ConfirmationReason.prompt`, and a case to `ConfirmedRouteTests.cases`, which covers the refusals. In Beekeeper, send it with `HiveLink.confirmed(_:_:body:reason:)`, giving a `reason` when the change is known to need confirming.
- **From D4:** Regenerate Identity unpairs every device and restarts Hive, and Beekeeper on the Hive Mac pairs again by itself (`HiveListStore.pairAgainAfterNewIdentity`). Another device then shows "This Hive's Identity Has Changed" (`HiveLink.Status.identityChanged`) and never accepts the new key; check that here, once a second device can pair. A device that pairs again gets a new device record and makes a new confirmation key the first time it needs one.

- **From F3:** after a restore, every device but Beekeeper on the Hive's Mac shows "This Hive's Identity Has Changed" for the same Hive ID. Pairing such a device again through a pairing code should replace its entry for that ID, as `HiveListStore.adoptRestoredHive` does on the Hive's Mac, rather than add a second one.

**Decisions (2026-11-11):**

- **Address options** are part of `HiveSettings` (`addressOptions`), saved through `PUT /settings` and audited (`addressOptionsChanged`). Each is a host, an IP address or DNS name, with its own port or none to follow the Hive's, for a port forward or a tunnel. At most 8. Hive checks only their form (`AddressOptionCheck`), and keeps them in recovery files. `GET /settings` labels each of the Mac's addresses (Tailscale's by its interface and address range, others by macOS's name for the interface) and suggests hosts: each address and the name a reverse lookup gives it, which for a Tailscale address is its MagicDNS name, plus the Mac's `.local` name (`SuggestedHostResolver`). Each suggestion names its address, so Beekeeper offers those that go with Listen on as chosen, before it's saved. The name, the network and the addresses share one Save, since which addresses work depends on where Hive listens.
- **Following the port:** `GET /hive` and live updates carry `HiveAddresses`, the port and the options with their ports. Live updates send them on connecting and on every change, and a device connected when the port changes keeps that response on the old listener, so it hears of the new port. A device that isn't connected then has to pair again. Beekeeper on the Hive's Mac only follows the port.
- **The pairing window** (`POST /pairing-window`, confirmed with `.pairingWindowOpened`) is kept in memory, one at a time: a new one closes the last, and restarting Hive closes it. It's refused with 422 while there are no address options, and 503 while Hive restarts. `GET` gives its state, including which device used it, and `DELETE` closes it. Opening, closing an unused window, and pairing through one (`pairedWithCode`, naming the device that opened it) are audited.
- **The code** is `hive1:` and base64url of the version, the Hive ID, the pin, a 128-bit token and the addresses with their ports, about 190 characters with three addresses (`PairingCode`). Copying it doesn't conceal it from clipboard managers or keep it local, since Universal Clipboard taking it to the new device is the point.
- **`POST /pairing`** is open in the gate. Every refusal without a good token is 404 with no body, and counts towards the same per-address lockout as sign-in (5 in 15 minutes, 15 minutes). A good token with a bad key or name gets 422 and an old API version 409, without using up the token. The API version went to 2, since older apps misread the new settings and live updates.
- **Connecting at several addresses:** `HiveConnection` tries the addresses in order from the last that worked, moving on when one can't be reached or shows another key, such as another machine at the Hive's old LAN address. A key refused at one address and shown at none is the identity having changed. Each request checks the pin with its own task delegate, since a session-wide flag would let one address's refusal mark the others. A request that timed out is only sent to the next address for a `GET`, since it may have reached Hive.
- **Beekeeper:** Pair a Device is on the Devices page, rather than in Settings, beside the list it adds to. Add Hive is in the File menu and the empty list, and a Hive not on this Mac that has to pair again offers Pair Again with a Code and Remove from Beekeeper. Pairing through a code replaces the list's entry for that Hive ID. Any Hive can be removed from Beekeeper through its sidebar row's context menu: when the Hive can be reached, Beekeeper revokes this device on it first, so the Hive's device list doesn't keep a device without a key. This also settles F3's follow-up about an identity-changed entry that couldn't be removed.

**Result (2026-11-11):** the tests pass. In the Debug build, the address options offered the Tailscale address and its MagicDNS name once Tailscale was chosen in Listen on, and the pairing window, its code and its cancellation showed in the audit log. In the installed builds, Beekeeper on a second Mac (Ivy) paired with the Hive by pasting a code and signed in over the tailnet; a used code and an expired code were refused; after regenerating the identity, Ivy showed "This Hive's Identity Has Changed", and pairing again with a new code replaced its entry; and removing the Hive from Beekeeper revoked the device on the Hive before pairing again.

**Done when:** Beekeeper on a second Mac pairs with the Hive by pasting a code and then signs in over the tailnet; an expired or used code is refused; D4's "identity changed" message shows on the second Mac after regenerating the identity; and the tests pass. The iOS Simulator has no Secure Enclave, so it can't stand in for the second device.
