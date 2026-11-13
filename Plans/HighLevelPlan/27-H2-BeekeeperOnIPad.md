# H2. Beekeeper on iPad

**Phase H — iPhone and iPad** · Mixed, 1–2 sessions, TestFlight

References like §15 point to [00-Info.md](00-Info.md).

## Engine

- **Bonjour** (§15): Hive advertises itself on every LAN interface it listens on, never on `127.0.0.1` or the tailnet, with a setting to turn it off. Beekeeper finds advertised Hives and fills in their address.
- **Secure Enclave keys on iPhone and iPad,** for signing in and for confirmed actions with Face ID or Touch ID (§6), kept where only Beekeeper can use them (B2)
- **The recovery file** kept on each device (F2)
- **Scanning the pairing QR code** with the camera, beside pasting the code (G1)

## UI

Built with you:

- **The Mac's layout, adapted for iPad,** with sheets where the Mac uses windows, and several Hives connected at once

**Done when:** on your iPad through TestFlight, Beekeeper pairs by scanning the QR code, shows live progress for a run, and deletes a snapshot on the test drive after Face ID or Touch ID; and the checks are added to [TestFlightChecks.md](TestFlightChecks.md).

## Decisions

- **Hive advertises one registration per interface,** through `dns_sd`, on each local network it listens on: multicast interfaces that are neither loopback nor point-to-point. Tailscale's `utun` is multicast-capable, so registering on every interface at once would include it. The advertisement is the Hive's name, with its ID in the TXT record (`hive=<ID>`). It follows the listeners, so it changes within a few seconds of an address appearing, the settings changing, or a rename.
- **The setting** is Advertise on the Local Network, on by default, in `HiveSettings.advertisesOnLocalNetwork`. It's recorded in the audit log and kept in recovery files. A Hive or Beekeeper from before it reads it as on, so the API version didn't change.
- **Beekeeper browses only once it has a Hive that isn't on its own Mac, or while Add a Hive is open,** so a Mac that only manages its own Hive is never asked for local network access.
- **A found address is tried before the Hive's own,** for sign-in and for pairing with a code, and isn't saved. Anything on the network can advertise any Hive ID, so another key at a found address counts as the Hive not being there, never as its identity changing.
- **The found address is the Bonjour host name,** such as `Karrin.local`, which resolves only on the local network.
- **Scanning uses VisionKit's `DataScannerViewController`,** and pairs as soon as it reads a whole code.
- **Face ID prompts** read "Allow Beekeeper to …", since iOS shows the reason as it is, where macOS puts "Beekeeper is trying to" before it.
- **Sheets keep their fixed sizes on the Mac only** (`macSheetSize`). iPadOS sizes its own.
