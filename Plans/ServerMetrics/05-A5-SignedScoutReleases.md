# A5. Signed Scout releases

**Phase A — Scout** · Engine, 1–2 sessions, needs you

References like §2 point to [00-Info.md](00-Info.md). Read `Scripts/release.sh` and `Scripts/sparkle-tools.sh` for how release keys are kept today.

Makes updates safe to hand to Hive (B3): the installed Scout accepts only a genuine, current release.

- **Two Ed25519 keys:** a release key and a development key, each with its private half in the Keychain, never in the repository. The public halves come from the gitignored `.xcconfig`, like Sparkle's, so someone building their own copy uses their own keys. A release Scout trusts only the release key; a development Scout only the development key.
- **What's signed:** a statement of Scout's version, the CPU type and the binary's SHA-256, not the binary alone, so an older genuine release can't be passed off as a newer one.
- **`hive-scout manage`** is how B3 drives Scout over SSH: no arguments, one request on standard input (status, install, update, enroll again, uninstall), so the `sudo` rule never has to allow arguments. For an update it:
  - reads the new binary and its signed statement into memory
  - checks the signature, that the CPU type is its own, that the hash matches, and that the version is newer than its own
  - writes the binary to a temporary file in `/usr/local/bin`, which only root can write, and renames it into place
  - restarts the service
  - never touches the state folder as root (A4)
- **The release script** builds both Linux binaries, signs their statements with the release key, attaches them to the GitHub release with their SHA-256s, and puts the binaries and statements in `Hive.app`'s `Contents/Resources`, since codesign treats `Contents/MacOS` as code. It stamps Scout's version, the download address and the hashes into both apps, for B2's pasted command and B3's updates. The third-party notices gain what the binary contains (musl, the Swift runtime, swift-crypto, SwiftNIO and NIOSSL).
- **Development builds** of Hive carry binaries signed with the development key, from `Scripts/build-scout.sh`, so B3 can be tested without a release.
- **Check that notarization accepts** Linux binaries in `Hive.app`'s resources, and note how much they add to the `.pkg` and Sparkle downloads.

## Tests

- `manage` refuses an unsigned binary, one signed with the other key, a statement for another CPU type, a hash that doesn't match, an older or the same version, and any arguments, and keeps running the version it has
- A binary swapped after its signature was checked is never what's installed
- A release Scout refuses a development-signed update, and the other way round

**Done when:** in the test VM, `manage` installs a newer development-signed Scout and refuses each case above; a rehearsal release (`Scripts/release.sh --rehearsal`) produces signed binaries inside a notarizable `Hive.app`; and the tests pass.
