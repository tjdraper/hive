# H1. iOS release script and first TestFlight build

**Phase H — iPhone and iPad** · Engine, 1 session, needs you

References like §2 point to [00-Info.md](00-Info.md). Copy from Locus Calendar: its `Scripts/release.sh` and `Plans/HighLevelPlan/05-A5-ReleaseScriptAndFirstTestFlightBuild.md`.

- **App Store Connect:** the app record and bundle ID for TestFlight. Needs you.
- **`Scripts/release.sh`** gains the iOS archive and upload to TestFlight, alongside G2's Mac release
- **The build date stamped into `Info.plist`,** for H4 (§16)
- **`install-test-build.sh`** gains `--iphone` and `--ipad`. Simulators have no Secure Enclave, so they show layouts but can't pair or sign in.
- **`NSLocalNetworkUsageDescription` and `NSBonjourServices`** in Beekeeper's iOS `Info.plist` (§17)
- **The privacy manifest**
- **[TestFlightChecks.md](TestFlightChecks.md)** gets its first checks

**Done when:** a TestFlight build installs on your iPhone and iPad and opens.
