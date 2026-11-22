# A5. Signed Scout releases

**Phase A — Scout** · Engine, 1–2 sessions, needs you

References like §2 point to [00-Info.md](00-Info.md). Read `Scripts/release.sh` and `Scripts/sparkle-tools.sh` for how release keys are kept today.

Makes updates safe to hand to Hive (B3): the installed Scout accepts only a genuine, current release.

- **Two Ed25519 keys:** Sparkle's signing key for releases, and a development key, each with its private half in the Keychain, never in the repository. The public halves come from the gitignored `.xcconfig`, so someone building their own copy uses their own keys. A release Scout trusts only Sparkle's key; a development Scout only the development key.
- **What's signed:** a statement of Scout's version, the CPU type and the binary's SHA-256, not the binary alone, so an older genuine release can't be passed off as a newer one.
- **`hive-scout manage`** is how B3 drives Scout over SSH: no arguments, one request on standard input (status, install, update, enroll again, uninstall), so the `sudo` rule never has to allow arguments. For an update it:
  - reads the new binary and its signed statement into memory
  - checks the signature, that the CPU type is its own, that the hash matches, and that the version is newer than its own
  - writes the binary to a temporary file in `/usr/local/bin`, which only root can write, and renames it into place
  - restarts the service
  - never touches the state folder as root (A4)
- **The release script** builds both Linux binaries, signs their statements with Sparkle's key, attaches them to the GitHub release with their SHA-256s, and puts the binaries and statements in `Hive.app`'s `Contents/Resources`, since codesign treats `Contents/MacOS` as code. It stamps Scout's version, the download address and the hashes into both apps, for B2's pasted command and B3's updates. The third-party notices gain what the binary contains (musl, the Swift runtime, swift-crypto, SwiftNIO and NIOSSL).
- **Development builds** of Hive carry binaries signed with the development key, from `Scripts/build-scout.sh`, so B3 can be tested without a release.
- **Check that notarization accepts** Linux binaries in `Hive.app`'s resources, and note how much they add to the `.pkg` and Sparkle downloads.

## Tests

- `manage` refuses an unsigned binary, one signed with the other key, a statement for another CPU type, a hash that doesn't match, an older or the same version, and any arguments, and keeps running the version it has
- A binary swapped after its signature was checked is never what's installed
- A release Scout refuses a development-signed update, and the other way round

**Done when:** in the test VM, `manage` installs a newer development-signed Scout and refuses each case above; a rehearsal release (`Scripts/release.sh --rehearsal`) produces signed binaries inside a notarizable `Hive.app`; and the tests pass.

## Session 1

Done: signed statements, `hive-scout manage`, the development key and signed development builds, `Hive.app` carrying the binaries, the release script's Scout steps, and the third-party notices. `Scripts/build-and-test.sh` passes, and everything in "done when" is true.

What was decided along the way:

- **Released Scouts trust Sparkle's signing key,** rather than a release key of their own, at your choice: it's the same kind of key, kept the same way and already backed up, and a second key in the same login Keychain would protect little. A statement begins `hive-scout release statement`, so no Sparkle signature over an update archive can pass for one, nor the other way round. The development key is Scout's own, kept by Sparkle's tools under the Keychain account `hive-scout-development`, with its public half in `SCOUT_DEVELOPMENT_PUBLIC_KEY`. `Scripts/build-scout.sh` exports the key into a private temporary folder for the moment it signs, through the tool that made it, so macOS doesn't ask for a password, and refuses to build when the Keychain's key isn't the public half in `Signing.local.xcconfig`. `--release` uses Sparkle's key and `UPDATES_PUBLIC_KEY`.
- **The public key reaches Scout** through `SCOUT_UPDATE_PUBLIC_KEY` at build time, which `Package.swift` hands to a one-function C target, since Swift's conditions can't carry a value. A build without one, such as `swift test` on the Mac, refuses every update.
- **A statement** is four lines of text (a heading, the version, the platform as `ScoutRelease.platform` names it, and the SHA-256) followed by a line with the Ed25519 signature over them. It's parsed only in the exact form it's written, so what's signed is what's read. Versions are three numbers. The version and platform signed are what the built binary reports itself through `manage`'s status, so a statement can't say something else.
- **`manage`** reads one line of JSON (`ManagementRequest`) on standard input, then for an update exactly the binary's length in bytes and nothing more, and answers with one line of JSON (`ManagementResponse`): done, refused (nothing changed) or failed. Status, install (with a code to enroll again, or without to keep the enrollment), update and uninstall. It takes no arguments. Install and uninstall are A4's workflows.
- **An update** checks, in order, root, Scout installed, a key built in, the statement's form, its signature, the platform, the hash of the binary held in memory, and that the version is newer; then stages the binary as `hive-scout.new` beside the installed one (refusing a link there), renames it into place, and runs the new binary's own `install`, with no code, so a release that changes its service brings the change and restarts.
- **`Hive.app` carries** `hive-scout-linux-{x86_64,aarch64}` and their `.statement`s in `Contents/Resources/Scout`, through a script phase that stops with a message when `Scripts/build-scout.sh` hasn't run. `build-scout.sh` now writes `build/scout/linux/`, with `Scout.xcconfig` (version and hashes, included by `Signing.xcconfig`) and `packages` (what the binaries link). Both apps' Info.plists carry `ScoutVersion`, `ScoutSHA256LinuxX86_64`, `ScoutSHA256LinuxAarch64` and `ScoutDownloadURL`, which only `release.sh` sets, to the release's GitHub download folder.
- **`Scripts/build-and-test.sh`** builds Scout for Linux before Hive, since Hive embeds it, and again when the binaries there were signed with Sparkle's key.
- **The release script** builds Scout with `--release`, checks each binary in `Hive.app` against its statement and both apps' hashes and verifies the statement against the Sparkle key, and adds the binaries, statements and `hive-scout-SHA256SUMS` to the release's downloads and the `gh release create` command. A rehearsal leaves `ScoutDownloadURL` empty, having nowhere a server could download from.
- **The notices:** Hive's list the packages Scout links (all already in Hive's), Swift's runtime, musl and mimalloc, from the SDK's `sbom.spdx.json`; their licenses are in `ThirdParty/scout/`. The SDK's other libraries (curl, libxml2, zlib and the rest) aren't linked into Scout. Beekeeper carries no binaries, so its notices don't change.
- **`Scripts/scout-test-vm.sh manage status|uninstall|update [<folder>]`** sends a request as Hive will, as `deploy` through Scout's rule.
- **Size:** the two binaries are 38 MB, and add about 15 MB to Sparkle's zip of `Hive.app` and 10–15 MB to the `.pkg`, which compresses better. The rehearsal's zip of `Hive.app` is 35.6 MB and its `.pkg` 35.5 MB.

Checked (2026-11-21):

- **Debian test VM:** installed 0.1.0 with `--ssh-user deploy` and a code from Beekeeper's Developer window. As `deploy` through the `sudo` rule, `manage` refused a statement with an empty signature, a version edited after signing, a statement signed with Sparkle's key, another CPU's binary, a hash that doesn't match, the same version, and an older development-signed one, each with the installed binary unchanged; an argument didn't get past `sudo`. It then updated to a development-signed 0.1.1, which restarted with its enrollment kept and reached Hive as 0.1.1, and uninstalled through `manage`, leaving no file, user, process or rule. Alpine with `doas` wasn't tried this session; `manage` there is the same code behind A4's checked `doas` rule.
- **Notarization:** `Scripts/release.sh --rehearsal 2026.4.90` built both apps with Sparkle-signed Scouts and passed its Scout checks. Its `Hive.app` zip, sent to Apple's notary service, was accepted with no issues: the Linux binaries in `Contents/Resources/Scout` are data to it. Stapled, Gatekeeper reads it as "Notarized Developer ID".
- **A4's thread priority line** comes from `enroll` only, run by `install`; `manage`'s update and uninstall didn't log it.

Follow-ups:

- **Ivy needs a Developer ID Installer certificate** before a real release, which signs the `.pkg`; only the Application certificate is in its Keychain. The 1Password CLI is installed and connected there.
