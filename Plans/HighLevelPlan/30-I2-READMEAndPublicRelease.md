# I2. README and public release

**Phase I — Open source release** · Mixed, 1 session, needs you

References like §17 point to [00-Info.md](00-Info.md).

- **The README** (§17): what Hive and Beekeeper are, how to build them with the `.xcconfig` template (copy `Configuration/Signing.template.xcconfig` to `Configuration/Signing.local.xcconfig`), that Xcode may ask once to trust the SwiftLint plugin before `xcodebuild` will build, that builds from free Apple accounts expire after 7 days, installing and approving the daemon, Full Disk Access, auto-login and the FileVault limitation (§4), the case-sensitive drive and copying files out of snapshots rather than editing them in place (§9), that every Hive Mac needs its own full Mac backup, and how to expose Hive safely (§5)
- **The security model,** briefly, for people deciding whether to trust it, with a way to report a vulnerability
- **The license** (§19), with the bundled rsync's GPLv3 license and where its source is
- **Checking the history for secrets** before the repository goes public (AGENTS.md)
- **Publishing signed builds** of both Mac apps with the release (G2)
- **Making the repository public** is yours to do

**Done when:** a fresh clone builds from the README alone with someone else's team ID, the history is clean, and the repository is public.
