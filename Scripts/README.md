# Releasing

```
Scripts/release.sh 2026.1
```

Hive and Beekeeper share one version and are released together, since they share the API. The script sets the version, archives both Mac apps, exports Developer ID builds, notarizes and staples them, builds Hive's installer package, and adds both apps to their appcasts in `docs/appcasts/`. It doesn't publish anything: it prints the `git` and `gh release create` commands to run, in the order that keeps the downloads live before the appcasts point at them.

A release has three downloads:

- **`Hive-<version>.pkg`** installs Hive the first time. Hive's daemon only runs from a `Hive.app` that root owns and only root can change (Plans §4), so dragging it from a zip isn't enough. The package installs it in `/Applications` owned by root, after asking for an administrator password, and can't be moved elsewhere by the installer.
- **`Hive-<version>.zip`** is what Sparkle downloads to update Hive.
- **`Beekeeper-<version>.zip`** installs and updates Beekeeper, which stays owned by you like any other app.

Versions are `YYYY.N`, or `YYYY.N.P` for a fix between releases. `CFBundleVersion` equals the version, so a version that shipped can't be rebuilt under the same name, and the script refuses a version that's already tagged. There's no beta channel.

The script refuses to run unless the working tree is clean and the branch is in step with its upstream, so the tag lands on the commit the build came from. If a release stops partway, undo the version and the appcast entries with `git checkout -- Hive.xcodeproj/project.pbxproj docs/appcasts`.

## Release notes

Required, in `docs/release-notes/<version>.md`, covering both apps. If they're missing, the script checks everything else first, then creates the empty file and stops. They're embedded in both appcasts, where Sparkle shows them as Markdown, and become the GitHub release's description. They don't need committing first; they go in with the release commit.

## Beekeeper for iPhone and iPad

```
Scripts/release.sh --testflight
```

Archives Beekeeper for iPhone and iPad from the working tree and uploads it to TestFlight for internal testers. It's separate from a Mac release, since TestFlight is also how work in progress reaches a real device, and uncommitted changes go into the build. After a release, run it from the release commit, so your devices have the released Beekeeper.

- **The version** is the project's, which is the last release's, so Beekeeper on a device never says a Hive has an update waiting when no update exists.
- **The build number** is a count that goes up by one with each upload, whatever the version, read from App Store Connect. A build about to expire is replaced by uploading the same version again.
- **The build date** is stamped into `Info.plist` as `BeekeeperBuildDate`. TestFlight builds stop opening 90 days after upload, and Beekeeper works out its expiry from it (Plans §16).

The archive is saved where Xcode's Organizer lists it. The script asks before uploading, since an upload can't be undone, and prints the date the build stops opening. Internal-only builds can never be sent to App Review, which Beekeeper never is.

## How the apps update

**Beekeeper** checks for updates with Sparkle, as the other Mac apps do, and has Check for Updates… in its app menu.

**Hive** updates through Sparkle in `Hive.app`, which only runs when you open it. Beekeeper notices when the Hive it's connected to is older than itself and says so on the Hive's overview, with an Open Hive button on the Hive's Mac. `Hive.app` checks for an update each time it opens. Only root can change `Hive.app`, so Sparkle asks for an administrator password, and gives the new copy the old one's owner, root. The running daemon notices that its executable was replaced and restarts, and launchd starts the new one. A backup running at that moment is cut short and picked up after the restart. Beekeeper reconnects on its own.

Installing a newer package over an installed Hive works the same way: the daemon restarts on the new version.

launchd reads the daemon's plist when Hive is turned on, not at each restart. A release that changes `HiveDaemon.plist` needs Remove Hive and Turn On Hive in `Hive.app`, and a new approval in Login Items.

## Trying an update before publishing

```
Scripts/release.sh --rehearsal 2026.0.1
Scripts/release.sh --rehearsal 2026.0.2
```

A rehearsal builds everything a release does, but on this Mac only: no git checks, no change to the project or `docs/`, no notarization, and appcasts in `build/rehearsal/appcasts/`. It prints how to install the build, how to serve `build/rehearsal/` on this Mac's loopback address, and how to point the installed apps at it with `defaults write <bundle ID> SUFeedURL`, which Sparkle prefers over the feed built into the app. Sparkle refuses `file://` URLs, and allows plain HTTP to the loopback address; every update is still checked against the Sparkle signing key. Install the first, point the apps at the rehearsal feed, then let them update to the second. Afterward, `defaults delete <bundle ID> SUFeedURL` puts them back on the published feeds.

A rehearsed version is installed like any other, so start real releases above it.

Builds from this Mac carry no quarantine flag, so Gatekeeper never checks them and skipping notarization makes no difference to the rehearsal.

## Copies you build yourself

The update feed and Sparkle's public key come from `UPDATES_SITE` and `UPDATES_PUBLIC_KEY` in `Configuration/Signing.local.xcconfig`. Left empty, the apps never update themselves, so a copy built and signed by someone else is never replaced by one of the published builds. Debug builds never update.

## One-time setup

### Developer ID certificates

Two, both from Xcode → Settings → Accounts → your Apple ID → Manage Certificates → **+**. Only the account holder can create them. If Xcode refuses, saying only the Account Holder can, make a certificate signing request with Keychain Access › Certificate Assistant › Request a Certificate From a Certificate Authority (saved to disk), upload it at developer.apple.com under Certificates → **+**, and double-click the downloaded `.cer`.

- **Developer ID Application** signs the apps.
- **Developer ID Installer** signs Hive's package.

`security find-identity -v -p basic` lists both once they're in the keychain.

### Notarization credentials

Notarizing uses the team's App Store Connect API key, the same one the other apps' release scripts use, read from 1Password at the start of each run. Touch ID asks once. The key is kept in a private temporary folder and deleted when the run ends, however it ends.

If the key isn't set up yet:

1. App Store Connect → Users and Access → Integrations → Team Keys → **+**, with the **Admin** role, and download the `.p8`. Apple only lets you download it once.
2. In 1Password, create an item named **Apple Developer Account Admin Key** in the **Private** vault, with the fields **Key ID** and **Issuer ID** (shown above the keys list), and attach `AuthKey_<Key ID>.p8`.
3. In 1Password → Settings → Developer, turn on **Integrate with 1Password CLI**, and install the CLI with `brew install 1password-cli`.

To keep the item somewhere else, set `HIVE_ASC_OP_ITEM` to its reference, such as `op://Work/Some Other Item`.

The key needs the **Admin** role: uploading to TestFlight from the command line creates and updates provisioning profiles.

### App Store Connect app record

For TestFlight. App Store Connect → Apps → **+** → New App, with only iOS ticked, Beekeeper's bundle ID (`<prefix>.HiveBeekeeper`), and a name of your choosing; App Store names are unique across all apps, so "Beekeeper" alone may be taken. The name only shows in TestFlight. The script looks the app up by bundle ID and stops if it isn't there.

Then, under TestFlight → Internal Testing, add a group with yourself in it and turn on automatic distribution, so each upload reaches your devices once Apple has processed it. Install the TestFlight app on each iPhone and iPad and sign in with the same Apple Account.

Beekeeper only uses the encryption built into iOS, so `ITSAppUsesNonExemptEncryption` is set to `NO` and TestFlight doesn't ask about export compliance for each build.

### Sparkle signing key

Sparkle signs each update with the EdDSA key in your login keychain, the one `Scripts/sparkle-tools.sh generate_keys -p` prints the public half of. Put that public half in `UPDATES_PUBLIC_KEY`. The release script checks that both apps carry it.

**Back the private key up somewhere safe.** Losing it means no installed copy can ever update again, short of everyone downloading the next release by hand.

```
Scripts/sparkle-tools.sh generate_keys -x sparkle-private-key.txt
```

Keep that file out of the repository. `sparkle-tools.sh` downloads Sparkle's command line tools into `build/tools/` the first time, checked against a pinned checksum.

### GitHub Pages

Repository Settings → Pages → deploy from branch `main`, folder `/docs`. That serves the appcasts at `https://tjdraper.github.io/hive/appcasts/`, which is the feed built into every release through `UPDATES_SITE = tjdraper.github.io/hive`. Confirm `https://tjdraper.github.io/hive/appcasts/hive.xml` loads before the first release.

If the feed ever moves to a custom domain, add it to the same Pages site rather than changing `UPDATES_SITE`. GitHub redirects the old address, so installed copies keep updating.

# Test builds

`Scripts/install-test-build.sh --mac-installed` builds Developer ID copies of the working tree and installs them in `/Applications`, Hive owned by root, without notarizing or touching the version or appcasts. It keeps the project's current version, so Sparkle may offer to replace it with a newer release.

`Scripts/install-test-build.sh --iphone` and `--ipad` build Debug Beekeeper for a simulator. Simulators have no Secure Enclave, so they show layouts but can't pair or sign in. Anything else on iPhone and iPad goes through TestFlight.
