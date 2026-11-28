# C3. Scout on other Macs

**Phase C — Alerts, Macs and release** · Engine, 1–2 sessions, installed build, needs you

References like §4 point to [00-Info.md](00-Info.md).

For Macs other than the Hive's, which reports itself (C2). Uses C2's macOS readers.

- **Which user it runs as:** depends on what C2 found an unprivileged process can see of other users' processes. Decide between a root daemon with nothing else to it and an unprivileged one that sees what Hive can, and record why.
- **`sudo hive-scout install`** writes a LaunchDaemon in `/Library/LaunchDaemons` and its state in `/Library/Application Support/Hive Scout/`, with A4's rules for the code and the state folder.
- **A universal binary,** signed with Developer ID and notarized by the release script, attached to the release beside the Linux ones, with its statement signed as in A5. A bare binary can be notarized but not stapled; a `curl` download isn't quarantined, so the Developer ID signature is what matters.
- **Installing from Beekeeper** (B3) works over SSH where the Mac has Remote Login on.

**Done when:** an installed Scout on a second Mac (Ivy) reports to the installed Hive, survives a restart, measures within §3's budget, updates through `manage`, and uninstalls cleanly; and the tests pass.

## Session 1

Done: Scout on macOS, installing it by hand, its tests, the signed universal binary, and the release script's Mac steps. Checked on Ivy. Installing from Beekeeper over SSH is left for session 2, so C3 isn't checked off.

What was decided along the way:

- **Scout on a Mac runs as root, but only to sample.** C2 found that only root can read other users' processes' CPU, memory and names (§11), and on a Mac those are most of what runs: Ivy shows 231 of 726 processes as other users' to an unprivileged process. A root daemon that does everything would put the network code, the key and Hive's answers in a root process. So launchd starts `hive-scout run` as root, which takes samples with C2's `MacSampler` and starts `hive-scout send`, which drops to `_hive-scout` for good before anything else and does the rest: the enrollment, the connection to Hive, and what's held. Samples go one way, one line of JSON each, down a pipe (`SampleHandover`); root reads nothing back, nothing from the network, and nothing in the state folder. Either process stopping ends the other, and launchd starts both again. SIGHUP reaches the root process and is passed on.
- **`sudo hive-scout install`** on a Mac makes a hidden system user and group, `_hive-scout`, with the highest free ID from 499 down, through `dscl`; makes `/usr/local/bin` if it isn't there; writes `/Library/LaunchDaemons/com.buzzingpixel.hive-scout.plist`; and keeps its state, and its status, in `/Library/Application Support/Hive Scout/`, `0700` and owned by `_hive-scout`. A Mac has no folder in memory like `/run`, so the status file is written every sample without `fsync`, which only the key needs. Running it again kickstarts the service, loads it again when its plist changed (launchd reads it only when it's loaded), or sends SIGHUP when only the code is new. Uninstall boots it out and removes the plist, binary, folder, user and group.
- **It refuses a binary folder others can change,** or the nearest folder above it, since root runs the binary: Homebrew on an Intel Mac owns `/usr/local/bin`. Linux installs check it too.
- **The LaunchDaemon** keeps Scout running, at nice 10 as a background process, which macOS gives the lowest CPU and I/O priority. launchd has nothing like systemd's `CPUQuota` or `MemoryMax`.
- **Logging:** launchd keeps no output, so on a Mac each line also goes to the system log under `com.buzzingpixel.HiveScout`. Nothing Scout logs carries its key or a code, so it's public.
- **One universal binary,** `hive-scout-macos-universal`, built by `Scripts/build-scout.sh` into `build/scout/macos/`, signed with Developer ID and the hardened runtime under the identifier `com.buzzingpixel.hive-scout`, timestamped for a release, with a statement for platform `macos-universal` signed as A5's are. Its hash is `SCOUT_SHA256_MACOS_UNIVERSAL` in `Scout.xcconfig`. It's 26 MB.

- **The release script** checks the Mac binary's Developer ID signature, hardened runtime, secure timestamp and statement, notarizes it zipped (a bare binary can't be stapled), and attaches it and its statement to the release, with its line in `hive-scout-SHA256SUMS`. Not yet rehearsed.

Checked on Ivy (2026-11-27), against the installed Hive, with a code from Beekeeper for a server without SSH details. Ivy is also the Hive Mac, so this tests Scout against its own Hive rather than a separate Mac.

- **Install:** `run` ran as root at nice 10 and `send` as `_hive-scout` (499, hidden); the state folder was `0700` and Scout's. Hive recorded Scout 0.3.0 on macOS 27.2, and each sample matched the Hive Mac's own at the same time: 640 processes, CPU, memory and swap, with no other users' line, since root sees every process (the Hive Mac's sampling shows 185 of the 640 that way).
- **Budget,** over 5 minutes: both processes together used 0.112% of a core, within §3's 0.15%, and 21 MB resident, 22 MB at the peak, which counts their shared libraries twice.
- **Update:** `manage` installed a development-signed 0.3.1 and restarted it, and refused the same version again. Hive recorded 0.3.1, with no gap in the samples.
- **Restart:** Ivy couldn't be restarted, so instead launchd unloaded Scout and loaded it again from its plist (`bootout`, `bootstrap`), and it was sending again at once. Stopping `send` made `run`'s next hand-over fail with a broken pipe, and launchd started both again at once, losing that one sample.
- **Uninstall** left no process, service, plist, binary, state folder, user, group or rule.

Left for session 2:

- **Installing from Beekeeper over SSH** (B3), where the Mac has Remote Login on: `Hive.app` carrying the Mac binary and its statement, the probe accepting Darwin with launchd, `ScoutRelease.Platform` gaining the Mac, `ScoutManagementCommand` checking the hash with `shasum -a 256` where `sha256sum` is missing, and Beekeeper's pasted command for a Mac, downloading `hive-scout-macos-universal`. A Mac's admin `sudo` asks for a password, so Hive's user gets Scout's `sudo` rule, which `/etc/sudoers.d` and `visudo` on macOS already allow.
- **A release rehearsal** (`Scripts/release.sh --rehearsal`) with the Mac binary.

Follow-ups:

- **Starting at boot** isn't checked: launchd loading the plist on its own when the Mac starts. Check the next time Ivy restarts.
- **On a Mac every line Scout logs goes to the system log,** including `install`'s prompt for the code, never the code itself.
