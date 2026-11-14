# I1. README and public release

**Phase I — Open source release** · Mixed, 1 session, needs you

References like §17 point to [00-Info.md](00-Info.md).

- **The README** (§17): what Hive and Beekeeper are, how to build them with the `.xcconfig` template (copy `Configuration/Signing.template.xcconfig` to `Configuration/Signing.local.xcconfig`), that Xcode may ask once to trust the SwiftLint plugin before `xcodebuild` will build, that builds from free Apple accounts expire after 7 days, installing and approving the daemon, Full Disk Access, auto-login and the FileVault limitation (§4), the case-sensitive drive and copying files out of snapshots rather than editing them in place (§9), that every Hive Mac needs its own full Mac backup, and how to expose Hive safely (§5)
- **The security model,** briefly, for people deciding whether to trust it, with a way to report a vulnerability
- **The license** (§19), with the bundled rsync's GPLv3 license and where its source is, already in `ThirdParty/rsync/` and `Hive.app`'s `Contents/Resources/rsync/` (C3)
- **Checking the history for secrets** before the repository goes public (AGENTS.md)
- **Publishing signed builds** of both Mac apps with the release (G2)
- **Making the repository public** is yours to do

**Done when:** a fresh clone builds from the README alone with someone else's team ID, the history is clean, and the repository is public.

**Done** (2026-11-14): `README.md`, `SECURITY.md` and an MIT `LICENSE`, with GitHub's private vulnerability reporting turned on. The repository was already public, with signed builds published since 2026.1. The history holds no secrets. Hive's team ID was in `project.pbxproj` between G2 and H1, but it's also in every published build's code signature, so the history was left as it is. A fresh clone built rsync, Beekeeper for iOS and both packages, and passed every test. The Mac builds with another team weren't tried, since that team has no account in Xcode on this Mac.

**Third-party notices** (2026-11-14): the published apps embed Sparkle, SwiftNIO, Hummingbird, GRDB and other packages under MIT and Apache 2.0, whose licenses ask for their notices to go with copies of the binaries. Both Mac apps show them in their About panels, from `ThirdPartyNotices.txt` files that `Scripts/write-third-party-notices.sh` writes from the packages each app actually links, read from the last build. `Scripts/build-and-test.sh` fails when they're out of date. Beekeeper for iPhone and iPad links no third-party code, and the script fails if that changes.
