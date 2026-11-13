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

## Decisions

- **TestFlight uploads are their own command,** `Scripts/release.sh --testflight`, apart from a Mac release. TestFlight is also how work in progress reaches a real device in H2 and H3, so it builds the working tree, uncommitted changes included. After a Mac release, it's run from the release commit.
- **The version is the project's,** the last release's, so Beekeeper on a device never says a Hive has an update waiting that doesn't exist (G2).
- **Build numbers are a count,** one more than the highest in App Store Connect, whatever the version. A build about to expire is replaced by uploading the same version again, which the Mac's version-as-build scheme can't do, and a `YYYY.N.P` version leaves no room for a fourth number.
- **The build date** is `BeekeeperBuildDate` in `Info.plist`, an ISO 8601 UTC time, set only by `--testflight` and empty in every other build (H4).
- **Internal TestFlight only,** since Beekeeper is never sent to App Review (§2).
- **`ITSAppUsesNonExemptEncryption` is `NO`.** Beekeeper only uses the encryption in iOS: `URLSession`'s TLS and CryptoKit. HiveKit doesn't link swift-crypto.
- **The privacy manifest** declares no tracking and no collected data, UserDefaults (`CA92.1`) and file timestamps (`C617.1`, the recovery file copies in Beekeeper's own container).
- **`NSLocalNetworkUsageDescription` and `NSBonjourServices`** are in the shared `Info.plist`, since macOS has the same local network permission.
- **The team ID** was in the project file since G2, written there by Xcode. It's back in `Signing.local.xcconfig` only.
