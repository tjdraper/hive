# G2. Mac release script and updates

**Phase G — Replacing site-backups** · Engine, 1–2 sessions, installed build, needs you

References like §2 point to [00-Info.md](00-Info.md). Copy from Locus Git Gui and Locus Launcher: `Scripts/release.sh`, `Scripts/sparkle-tools.sh`, `Scripts/README.md` and `docs/appcast.xml`.

- **One version number for Hive and Beekeeper,** released together, since they share the API
- **`Scripts/release.sh`:** version and build, archives of both Mac apps, Developer ID export, notarizing and stapling (including the bundled rsync), the appcast, release notes and the GitHub release, printing the publishing commands as the other apps' scripts do
- **Sparkle for Beekeeper on the Mac,** as in the other apps
- **Installing `Hive.app` owned by root** (§4, A2): the daemon refuses to start otherwise, so dragging it from a disk image isn't enough. Most likely a `.pkg` installer, which installs owned by root and asks for an administrator password. Hive's window already tells you when the install isn't owned by root.
- **Hive updating itself** (§19). Each update replaces a root-owned bundle and keeps it root-owned, so it needs an administrator password, for example through Sparkle's installer for apps the user can't write to, or a new `.pkg`. `Hive.app` isn't running most of the time, so decide how, for example: Beekeeper shows "Update available" and opens `Hive.app`, which runs Sparkle and restarts the daemon from the new bundle; or the daemon checks the appcast itself and exits so launchd starts the new version. Record the decision in §2.
- **When Hive and Beekeeper versions differ,** the API version check from B2 tells you which one to update
- **Signing secrets** from the Keychain and environment, never the repository (AGENTS.md). Needs you for the Sparkle key and the notarization profile.

**Done when:** a release build of both apps updates through Sparkle from the one before; Hive restarts on the new version and Beekeeper reconnects; and the release script stops before publishing, as the other apps' does.
