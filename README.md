# Hive

Hive backs up servers. It runs in the background on a Mac, pulls directories over rsync and SSH and dumps MySQL, MariaDB and Postgres databases, and keeps them as incremental snapshots on a drive attached to that Mac.

Beekeeper is the manager app for Mac, iPad and iPhone. One Beekeeper can manage several Hives.

- Snapshots are ordinary folders you can browse in Finder. Unchanged files are hard links to the previous snapshot, so they take no extra space.
- Each job keeps one snapshot from each of its newest days and months, with an optional space limit for each server.
- Databases can run on the server or in Docker containers, found by their Swarm or Compose service name.
- Email alerts for failed backups, a missing drive, overdue jobs, changed host keys and low space.
- Live progress, a job log, and an audit log of every change.

Hive needs macOS 26 or later. Beekeeper needs macOS, iOS, or iPadOS 26 or later.

## Installing

Download `Hive-<version>.pkg` and `Beekeeper-<version>.zip` from the [latest release](https://github.com/tjdraper/hive/releases/latest) onto the Mac that will run Hive.

1. Open the package to install Hive. It asks for an administrator password.
2. Open Hive and choose **Turn On Hive**, then approve Hive in System Settings › General › Login Items. Hive starts at boot from then on, and runs as your user, not root.
3. Give the entry named **Hive** Full Disk Access in System Settings › Privacy & Security, so it can write to the backup drive. Hive's window has a button for each of these settings.
4. Unzip Beekeeper, move it to Applications and open it. On the Hive Mac it pairs with Hive by itself.
5. Beekeeper walks you through the rest: the recovery key, the backup drive and email.

**Save the recovery key in a password manager.** Beekeeper shows it once. Without it, Hive can't be brought back on another Mac with its settings and keys.

### The Hive Mac

- **Keep auto-login on.** macOS mounts external drives only once someone logs in, and Tailscale's Mac app only runs then. Hive itself starts at boot.
- **FileVault** works, but a Mac with FileVault on that restarts unexpectedly waits at the unlock screen, and Hive doesn't run until someone unlocks it. For planned restarts, `sudo fdesetup authrestart` skips that.
- **Don't let it sleep.** Jobs missed while it slept run once it wakes. Hive warns when the Mac is set to sleep.
- **Back the Hive Mac up**, with Time Machine, Arq or similar. Hive doesn't back up its own Mac or its drive. Its data folder, `~/Library/Application Support/Hive/`, holds the configuration and copies of the recovery file.
- **To change the account Hive runs as**, log in as that account and run `sudo /Applications/Hive.app/Contents/MacOS/HiveDaemon reset-user`.

### The backup drive

The drive must be **APFS (Case-sensitive)**. Linux servers can have `Foo.jpg` and `foo.jpg` in one folder, and a case-insensitive drive keeps only one of them. You don't have to erase an existing APFS drive: in Disk Utility, select it and choose Edit › Add APFS Volume, with the format APFS (Case-sensitive).

Hive knows the drive by its volume ID, not its name, and never writes while it isn't mounted.

### Snapshots

Each run makes a folder at `Hive/<server>/<job>/<date and time>/` on the drive, with directories under `files/`, database dumps under `databases/`, and a `manifest.json`.

**Copy files out of a snapshot. Never edit them where they are.** A file that didn't change between runs is one file shared by every snapshot that has it, so editing it in place changes it in all of them.

Owners and groups are kept as extended attributes on each file, since Hive runs as a normal user and can't set them.

### Servers

Each server needs `rsync` 3 and SSH access for a user that can read what you back up. Databases in Docker need that user to be able to run `docker`.

When you add a server, Beekeeper shows its host key fingerprint to confirm, and the public half of the SSH key Hive made for it, to add to the server's `~/.ssh/authorized_keys`. Each server gets its own key.

If a server's host key changes, its backups stop and Hive emails you daily until you confirm the new key in Beekeeper.

### Other devices and the network

Hive always listens on `127.0.0.1`, for Beekeeper on its own Mac. To reach it from other devices, add one of the Mac's addresses in the Hive's network settings in Beekeeper, such as its Tailscale address, or all of them. The port is 4483.

To pair another device, choose **Pair a Device…** under Devices in Beekeeper on a paired device, then scan the QR code or paste the pairing code on the new one.

To reach Hive from the internet, forward its port, or use a tunnel that passes TCP straight through. TLS has to end at Hive, never at a proxy in front of it: Beekeeper checks that it is talking to Hive's own key and refuses anything else. Tailscale or another VPN is still the better choice.

See [SECURITY.md](SECURITY.md) for how connections, devices and secrets are protected.

### Restoring on a new Mac

Install Hive and Beekeeper on the new Mac as above, and restore the backup drive from its own backup if it was lost. In Beekeeper, choose **Restore from a Recovery File…**, pick the newest recovery file, and enter the recovery key. Then choose the backup drive again. Hive keeps the same ID, takes over the snapshots on the drive, and waits for you to start retention and quotas, in case a restored drive lost its hard links.

Other devices have to pair again, since the new Mac has a new key.

## Beekeeper on iPhone and iPad

There are no published iPhone or iPad builds as getting the app through app store approval sounds like a nightmare. But, you can build Beekeeper yourself. It pairs with any Hive, including one installed from the published builds.

Builds signed with a free Apple account stop opening after 7 days. Running from Xcode again renews them. With a paid account, a TestFlight build lasts 90 days. Hive emails before a build expires, and Beekeeper's device list shows when each one does.

## Building

You need Xcode 27.2, the version Hive is developed with, and an Apple Developer account.

1. Copy `Configuration/Signing.template.xcconfig` to `Configuration/Signing.local.xcconfig`, which git ignores, and fill in your team ID and a bundle ID prefix, such as `com.example`. Leave the update settings empty unless you publish your own builds.
2. Run `Scripts/build-rsync.sh`. Hive bundles rsync 3, built from source, and Xcode won't build Hive until it's there.
3. Open `Hive.xcodeproj`. Xcode asks you to trust the SwiftLint plugin the first time, and `xcodebuild` won't build until you have.

`Scripts/build-and-test.sh` builds everything and runs the tests, and fails on any warning. It also fails when the third-party notices in the apps' About panels no longer match the packages they link. After adding or updating a package, run it, then `Scripts/write-third-party-notices.sh`.

Hive itself has to be installed to run, owned by root, from a Developer ID build, which needs a paid account. `Scripts/install-test-build.sh --mac-installed` builds both Mac apps and installs them in `/Applications`. Beekeeper only pairs itself with a Hive on the same Mac when both come from the same developer team, so a Hive you build needs a Mac Beekeeper you built too. On other devices, any Beekeeper can pair.

## License

Hive and Beekeeper are under the [MIT License](LICENSE).

`Hive.app` includes [rsync](https://rsync.samba.org), unmodified, as a separate program under the GNU General Public License version 3. Its license is in [`ThirdParty/rsync/`](ThirdParty/rsync/) and in `Hive.app` at `Contents/Resources/rsync/COPYING`. `Scripts/build-rsync.sh` names the exact source it's built from.

The other third-party software in each Mac app, with its licenses, is listed in the app's About panel.
