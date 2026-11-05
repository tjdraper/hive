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

## Tests

- A token works once, never after it expires, and never while no window is open
- Opening a window without confirmation is refused
- A pairing code with a wrong key hash fails to connect
- Repeated wrong tokens lock out that address

**Done when:** Beekeeper on a second Mac pairs with the Hive by pasting a code and then signs in over the tailnet; an expired or used code is refused; D4's "identity changed" message shows on the second Mac after regenerating the identity; and the tests pass. The iOS Simulator has no Secure Enclave, so it can't stand in for the second device.
