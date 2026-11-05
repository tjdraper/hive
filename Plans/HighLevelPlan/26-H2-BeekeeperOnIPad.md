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
