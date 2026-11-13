# H3. Beekeeper on iPhone

**Phase H — iPhone and iPad** · UI, 1–2 sessions, TestFlight

References like §15 point to [00-Info.md](00-Info.md).

Built with you:

- **iPhone's own layout** for the list of Hives, servers, jobs, status, snapshots and logs, and the settings and devices screens
- **Several Hives at once,** with their status in the list
- **Pairing** by scanning the QR code (H2)

- **From H1:** on iPhone, `MainWindow`'s split view collapses to the sidebar, which is empty with no Hives, with a disabled Add Server at the bottom. The first-run screen, `EmptyHiveList`, is in the detail column and never shows.

**Done when:** on your iPhone through TestFlight, Beekeeper pairs by scanning the QR code, shows live progress for a run, and deletes a snapshot on the test drive after Face ID; and the checks are added to [TestFlightChecks.md](TestFlightChecks.md).
