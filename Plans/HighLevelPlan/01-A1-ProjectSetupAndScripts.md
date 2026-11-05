# A1. Project setup and scripts

**Phase A — Foundations** · Engine, 1 session

References like §3 point to [00-Info.md](00-Info.md).

- **An Xcode project, `Hive.xcodeproj`** (§3), with:
  - `Hive`: the Mac app that will install the daemon. For now it shows an empty window.
  - `HiveDaemon`: a command-line executable embedded in `Hive.app`. For now it logs that it started, then exits.
  - `Beekeeper`: one multiplatform app target for Mac, iPad and iPhone, with an empty window.
  - `HiveKit` and `HiveCore` as local Swift packages, each with a placeholder test. HiveKit builds for macOS and iOS, HiveCore for macOS.
- **Signing from a gitignored `.xcconfig`** holding the team ID and bundle ID prefix, with a checked-in template (§17). Bundle IDs are built from the prefix. Nothing team-specific goes in the project file.
- **Minimum OS versions:** macOS 26, iOS 26 and iPadOS 26. Hardened runtime on the Mac targets, and no App Sandbox (§2).
- **Swift 6,** with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` for Beekeeper only (§3).
- **SwiftLint** through the SwiftLintPlugins package, with Locus Write's `.swiftlint.yml` adapted: its UI-framework rule covers HiveKit, HiveCore and HiveDaemon.
- **`.gitignore`**, already copied from Locus Launcher: check it covers the `.xcconfig` name chosen here and anything the scripts write outside `build/`.
- **Log subsystems** `com.buzzingpixel.Hive` and `com.buzzingpixel.HiveBeekeeper`, matching AGENTS.md.

## Scripts

Copied from Locus Write and Locus Calendar, and adapted:

- `Scripts/build-and-test.sh`: builds Hive for macOS and Beekeeper for macOS and the iOS Simulator, runs both packages' tests, and fails on any warning, SwiftLint's included
- `Scripts/install-test-build.sh` with `--mac`, `--mac-installed` and `--simulator <name>`. `--mac-installed` installs both Mac apps in `/Applications`, signed with Developer ID. A2 adds restarting the daemon. The iPhone and iPad options wait for Phase H.
- `Scripts/TestBuildExportOptions.plist` for the Developer ID export
- The `TEST_BUILD` compilation condition, set by `--mac-installed`

**Done when:** `Scripts/build-and-test.sh` passes with zero warnings and the placeholder tests pass; `install-test-build.sh --mac-installed` puts Hive and Beekeeper in `/Applications` and both open; and a fresh clone with only the template filled in builds.
