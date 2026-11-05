# Hive — High-Level Plan

This folder is the plan for Hive's first version: Hive running on its Mac, backing up servers incrementally, managed from Beekeeper, and replacing `site-backups`. This file holds what's being built and how the work is done. Each slice of work has its own file, numbered in order. Start every session by reading this file and the slice's file.

[initial-brainstorm.md](../initial-brainstorm.md) records the reasoning behind the connection and security design, in more detail than this file. Security slices name the parts of it to read. Where the two differ, this plan wins.

---

## Checklist

Check off a slice here when its "done when" is true.

### Phase A — Foundations

- [x] [A1. Project setup and scripts](01-A1-ProjectSetupAndScripts.md) — Engine, 1 session
- [x] [A2. Installing the daemon](02-A2-InstallingTheDaemon.md) — Mixed, 1–2 sessions, installed build, needs you
- [x] [A3. App icons](03-A3-AppIcons.md) — UI, 1 session, needs you
- [ ] [A4. Secure Enclave keys and secrets](04-A4-SecureEnclaveKeysAndSecrets.md) — Engine, 1 session, installed build, needs you

### Phase B — Connecting Beekeeper on the Mac

- [ ] [B1. The TLS server](05-B1-TheTLSServer.md) — Engine, 1 session, installed build
- [ ] [B2. Pairing on the Hive Mac and signing in](06-B2-PairingOnTheHiveMacAndSigningIn.md) — Engine, 1–2 sessions, installed build
- [ ] [B3. Beekeeper's window, devices and settings](07-B3-BeekeepersWindowDevicesAndSettings.md) — Mixed, 1–2 sessions, installed build

### Phase C — Backups in Hive

- [ ] [C1. Servers and backup jobs](08-C1-ServersAndBackupJobs.md) — Engine, 1 session
- [ ] [C2. SSH keys, host keys and the test server](09-C2-SSHKeysHostKeysAndTheTestServer.md) — Engine, 1 session
- [ ] [C3. Directory snapshots](10-C3-DirectorySnapshots.md) — Engine, 1–2 sessions, installed build
- [ ] [C4. Database dumps](11-C4-DatabaseDumps.md) — Engine, 1 session
- [ ] [C5. Scheduling, the job queue and the job log](12-C5-SchedulingTheJobQueueAndTheJobLog.md) — Engine, 1 session
- [ ] [C6. Retention and quotas](13-C6-RetentionAndQuotas.md) — Engine, 1–2 sessions

### Phase D — Managing backups in Beekeeper (Mac)

- [ ] [D1. Servers in Beekeeper](14-D1-ServersInBeekeeper.md) — UI, 1 session
- [ ] [D2. Editing backup jobs](15-D2-EditingBackupJobs.md) — UI, 1 session
- [ ] [D3. Progress, snapshots and logs](16-D3-ProgressSnapshotsAndLogs.md) — Mixed, 1–2 sessions
- [ ] [D4. Confirming destructive actions](17-D4-ConfirmingDestructiveActions.md) — Mixed, 1–2 sessions, installed build

### Phase E — Email

- [ ] [E1. Sending email](18-E1-SendingEmail.md) — Mixed, 1 session
- [ ] [E2. Alerts](19-E2-Alerts.md) — Engine, 1 session

### Phase F — Recovery

- [ ] [F1. Recovery key and recovery files](20-F1-RecoveryKeyAndRecoveryFiles.md) — Mixed, 1–2 sessions
- [ ] [F2. Recovery file copies in Beekeeper](21-F2-RecoveryFileCopiesInBeekeeper.md) — Mixed, 1 session
- [ ] [F3. Restoring Hive on a new Mac](22-F3-RestoringHiveOnANewMac.md) — Mixed, 2 sessions, installed build, needs you

### Phase G — Replacing site-backups

- [ ] [G1. Pairing more devices](23-G1-PairingMoreDevices.md) — Mixed, 1–2 sessions, installed build, needs you
- [ ] [G2. Mac release script and updates](24-G2-MacReleaseScriptAndUpdates.md) — Engine, 1–2 sessions, installed build, needs you
- [ ] [G3. Moving off site-backups](25-G3-MovingOffSiteBackups.md) — Mixed, 1 session, needs you

### Phase H — iPhone and iPad

- [ ] [H1. iOS release script and first TestFlight build](26-H1-IOSReleaseScriptAndFirstTestFlightBuild.md) — Engine, 1 session, needs you
- [ ] [H2. Beekeeper on iPad](27-H2-BeekeeperOnIPad.md) — Mixed, 1–2 sessions, TestFlight
- [ ] [H3. Beekeeper on iPhone](28-H3-BeekeeperOnIPhone.md) — UI, 1–2 sessions, TestFlight
- [ ] [H4. Build expiry warnings](29-H4-BuildExpiryWarnings.md) — Engine, 1 session, TestFlight

### Phase I — Open source release

- [ ] [I1. README and public release](30-I1-READMEAndPublicRelease.md) — Mixed, 1 session, needs you

---

## Milestones

| Milestone | What you can do | Slices |
| --- | --- | --- |
| M1. Hive runs | Install Hive on the Mac, approve it once, and have it start at boot as your user, with its keys in the Secure Enclave | A1–A4 |
| M2. Beekeeper connects | Open Beekeeper on the Hive Mac, have it pair itself, and see the Hive, its devices and its settings | B1–B3 |
| M3. Backups run | Set up servers and backup jobs in Beekeeper on the Mac, and have Hive back them up on schedule into hard-link snapshots, with retention, quotas, live progress and logs | C1–C6, D1–D4 |
| M4. Safe to rely on | Email alerts when something goes wrong, and a way to bring Hive back on a new Mac | E1–E2, F1–F3 |
| M5. site-backups retired | Manage the Hive from another Mac, with signed, updatable builds backing up your real servers, and the PHP version turned off | G1–G3 |
| M6. iPhone and iPad | Beekeeper on iPhone and iPad, and warnings before their builds expire | H1–H4 |
| M7. Open source | A README and published builds | I1 |

---

# Part 1 — What we're building

## §1. The apps

- **Hive** runs on one dedicated Mac, as a background service with no interface of its own. In this plan it backs up servers: directories through rsync over SSH, and MySQL, MariaDB and Postgres databases, kept as incremental snapshots on a drive attached to the Hive Mac. It replaces `site-backups` (`../site-backups`), and gains more features in later plans (§18).
- **Beekeeper** is the only way to manage a Hive, on Mac, iPad and iPhone. One Beekeeper can manage several Hives.
- **How Beekeeper shows a Hive's contents.** This is the hierarchy you navigate in Beekeeper, not a folder layout for the code, which is organized by user flow (`Architecture/README.md`). Hive's data follows the same shape (§8).

  ```
  Hive
  └── Servers
      └── Backup jobs
  ```

  A machine hosting several sites is one server, with a backup job for each site. Server stats, heartbeats and HTTP status checks will sit under servers in later plans (§18).

## §2. Platforms and distribution

- **Hive:** macOS only. macOS 26 runs only on Apple silicon and T2 Macs, all of which have the Secure Enclave Hive needs (§7).
- **Beekeeper:** macOS, iPadOS and iOS. The Mac comes first. iPhone and iPad follow in Phase H, once backups run end to end and the PHP version is retired.
- **Minimum OS versions:** macOS 26, iOS 26 and iPadOS 26.
- **The Mac apps** ship with Developer ID and notarization, and update through Sparkle. They aren't on the App Store and don't use the App Sandbox.
- **Beekeeper for iPhone and iPad** goes on your devices through internal TestFlight builds, or ad hoc builds as a fallback. Other people build their own.
- **Open source** (§17).

## §3. Architecture

- **Four parts:**
  - **`Hive.app`:** a small Mac app that installs and registers the daemon, with the daemon's executable inside its bundle.
  - **`Beekeeper`:** one multiplatform app target for Mac, iPad and iPhone.
  - **`HiveKit`:** a Swift package with the API types, the XPC pairing messages and the client. Beekeeper uses it on every platform, and Hive uses its API types. Nothing else goes in it (`Architecture/README.md`).
  - **`HiveCore`:** a Swift package with everything Hive does that can be tested without running the daemon: the store, the HTTP routes, signing in, the backup engine, retention and scheduling. macOS only. The daemon's executable connects it to the real Secure Enclave, network and processes.
- **The server is Hummingbird 2** on SwiftNIO, for TLS, routing and WebSockets. Routes are tested with Hummingbird's test client, which never opens a port.
- **Hive's store is SQLite through GRDB.** It works from a daemon off the main actor, its migrations are explicit, and nothing about it needs syncing. It holds the configuration, the job queue, the catalog of snapshots, the job log and the audit log.
- **Beekeeper's store is a small file on each device,** never synced: the list of Hives and, for each, its addresses and pinned key hash. This device's keys for each Hive are kept where only Beekeeper can use them (B2). Each device pairs on its own.
- **The API is HTTPS with JSON** for commands, plus a **WebSocket** for live progress and logs.
- **Concurrency:** Hive and both packages are nonisolated by default, and Beekeeper is main-actor by default (AGENTS.md).
- **Names:** bundle IDs are built from the prefix in the gitignored `.xcconfig` (§17). The log subsystems are fixed in code: `com.buzzingpixel.Hive` and `com.buzzingpixel.HiveBeekeeper`.
- **SwiftLint** runs through the SwiftLintPlugins package, with Locus Write's `.swiftlint.yml` and a rule that keeps AppKit, UIKit and SwiftUI out of HiveKit, HiveCore and the daemon.

## §4. How Hive runs

- **As a LaunchDaemon,** registered with `SMAppService.daemon` from `Hive.app` and approved once in System Settings › General › Login Items.
- **`Hive.app` shows one small window and no settings:** whether the daemon is approved and running, buttons to the Login Items and Full Disk Access settings, and a button to open Beekeeper.
- **The daemon starts at boot without anyone logged in,** with FileVault on or off. With FileVault on, an unexpected restart leaves the Mac at the unlock screen and Hive doesn't run until someone unlocks it. `fdesetup authrestart` avoids that for planned restarts. Beekeeper only sees that Hive is offline.
- **Your Hive Mac keeps auto-login on for now.** Tailscale's Mac app only runs once someone is logged in, and your servers are reached over the tailnet. macOS also mounts external drives at login. Running with nobody logged in is later work (§18).
- **After starting, Hive waits a few minutes for the backup drive** before running overdue jobs, so a drive that mounts late doesn't fail every job at boot.
- **It runs as the user who installed it, never as root once started.** launchd starts it as root. On its first start, right after approval, it records the user logged in at the screen in a root-owned file under `/Library/Application Support/Hive/`. On every start it reads that file, then permanently gives up root (`initgroups`, `setgid`, `setuid`) and confirms root can't be regained. Nothing touches the network, keys or secrets while it's root.
- **Data directory:** `~/Library/Application Support/Hive/` in that user's home folder, so the regular Mac backup includes it.
- **`Hive.app` is installed owned by root,** writable only by root, and the daemon refuses to start from a bundle anyone else can change. A2 found that App Management doesn't stop the user's other programs from changing a locally built `Hive.app`, and that a fresh registration starts whatever executable is in the bundle at that moment. launchd does refuse a changed executable under an existing registration, and macOS withdraws the approval, so getting root that way always needs a new approval in Login Items. Root ownership closes the in-place change. An administrator account can still rename `Hive.app` within `/Applications`, which also needs a new approval. Installing and updating `Hive.app` therefore needs an administrator password (G2).
- **Changing the user** is a reset command run on the Hive Mac, which needs an administrator password. It isn't available from Beekeeper.
- **Full Disk Access** is granted once, to the "Hive" entry macOS lists for the daemon (it's tied to `Hive.app` through `AssociatedBundleIdentifiers`), so it can write to the backup drive. A daemon can't ask for it, so Beekeeper warns while Hive doesn't have it.

## §5. The network and TLS

Read the brainstorm's "Guiding principle", "Encryption: always TLS" and "Hardening for internet exposure".

- **Hive gives the network no trust.** The tailnet is treated exactly like the open internet.
- **Always TLS, with no plain HTTP mode.** The certificate is self-signed for a P-256 identity key in the Secure Enclave, made with `swift-certificates` and valid for 10 years. SwiftNIO's TLS signs through `NIOSSLCustomPrivateKey`, so the private key never exists as a file.
- **Beekeeper pins the public key's hash,** and ignores the chain, hostname and expiry. Hive can reissue the certificate for the same key without breaking any device.
- **Regenerate identity** creates a new key. Every device has to pair again.
- **Listen address:** Hive always listens on `127.0.0.1`, for Beekeeper on the Hive Mac. The setting adds one interface, such as Tailscale's, or all of them, and adds none by default. An interface that appears after Hive starts, such as Tailscale's after login, is picked up when it appears. The port is configurable.
- **Exposing Hive to the internet** means forwarding the port or using a tunnel that passes TCP through. TLS always ends at Hive.
- **Unauthenticated requests reach only** the challenge endpoint, the pairing endpoint while a pairing window is open, and a minimal health check. Everything else is refused before routing or parsing.
- **Rate limiting and lockout** for failed sign-ins and pairing attempts, per address and per device. Never for everyone at once, which would let anyone on the internet lock you out.

## §6. Pairing and signing in

Read the brainstorm's "Authentication: a key per device, with no passwords" and "Managing several Hives".

- **Each device creates a P-256 key in its Secure Enclave for each Hive.** Hive records its public key and a device name. Every paired device has full access, with no roles. Two Hives can't tell that the same device is paired with both.
- **The first device is Beekeeper on the Hive Mac,** paired over XPC through the daemon's Mach service. Hive checks the caller's code signature from its audit token: the same team ID as Hive, and Beekeeper's bundle ID. XPC is used only for pairing. Afterwards that Beekeeper uses the HTTPS API on `127.0.0.1` like every other device. Being on the same Mac never skips signing in.
- **More devices** pair through a window opened by a paired Beekeeper: a QR code, or a pairing code to copy, single-use and expiring in about 5 minutes, carrying the Hive ID, the address options, the key hash and a one-time token (G1).
- **Signing in:** Hive sends a challenge with a nonce and an expiry, Beekeeper signs it, and Hive returns a short-lived session token for HTTP and the WebSocket. The signature isn't bound to the TLS connection, because SwiftNIO's TLS doesn't expose the TLS exporter that needs (checked 2026-11-04). The key pin, the fresh nonce and short-lived session tokens protect signing in instead. Beekeeper reports its build details at the same time (§16).
- **Actions that need confirmation** use a second Secure Enclave key protected by `.userPresence`, so Face ID, Touch ID or the account password is asked even in an open session:
  - deleting snapshots
  - lowering a server's quota or a job's retention tiers, which would delete snapshots
  - changing a server's host, port or SSH user, or its credentials (database passwords and Hive's SSH key)
  - confirming a changed host key
  - opening a pairing window, since a new device gets full access
  - regenerating the identity, rotating SSH keys, and making a new recovery key
- **Devices:** Beekeeper lists every paired device with when it was last seen, and can revoke any of them at once.

## §7. Secrets and keys at rest

Read the brainstorm's "Secrets and keys at rest".

- **Two Secure Enclave keys:** the identity key (P-256 signing, for TLS) and the storage key (P-256 key agreement, for secrets). Their `dataRepresentation` blobs, which only this Mac's Secure Enclave can use, are stored as `0600` files in the data directory. No keychain.
- **Each secret is encrypted on its own:** a temporary key, ECDH with the storage key, HKDF, then AES-GCM. Only the result is written to disk, and secrets are decrypted in memory when needed.
- **Secrets are** SSH private keys, database passwords, the SMTP password and any future credentials. They're write-only through the API.
- **A secret is never sent somewhere new without being entered again.** Changing a server's host, port or user clears its jobs' database passwords, and changing the SMTP host clears the SMTP password. Otherwise a stolen session could point Hive at another machine and collect them.
- **A copy of the data directory is useless on any other machine.** Bringing Hive back goes through a recovery file (§14).
- **Checked first** (A4): Secure Enclave keys work from the daemon after it switches user, outside any login session. Everything here depends on it.

## §8. Servers and backup jobs

Configuration is data, edited in Beekeeper. The PHP configuration (`../site-backups/config/Dependencies/BackupConfigBindings.php`) is a starting point, not a rule.

- **A server** is a machine, entered once: a name, a host, a port, an SSH user, its confirmed host key (§11), Hive's SSH key for it, and a quota (§10).
- **A backup job** belongs to one server, usually one for each site on it, and has:
  - a name
  - directories: a path on the server, and the folder it goes in within each snapshot, which can be nested, such as `images/galleries`
  - databases: MySQL/MariaDB or Postgres, running in a Docker container (found by its service name, §11) or on the host, with a user, password and database name
  - one or more times a day to run
  - retention tiers (§10)
- **Every change goes in the audit log** (§12).

## §9. How backups are stored

- **One backup drive per Hive,** attached to the Hive Mac and formatted **case-sensitive APFS**. Linux servers can hold `Foo.jpg` and `foo.jpg` side by side, and a case-insensitive drive keeps only one. A case-sensitive volume can be added to an existing APFS drive without erasing it.
- **Hive knows the drive by its volume UUID,** never by its path, and never writes while it isn't mounted. When a drive is missing, its mount point under `/Volumes` is just a folder on the startup disk.
- **Hard-link snapshots.** Each run makes a new snapshot folder with `rsync --link-dest`, pointing at the job's last complete snapshot. Unchanged files are hard links and take no extra space. A changed file is stored whole. Every snapshot is an ordinary folder that can be browsed in Finder and copied out by hand.
- **A file in a snapshot is shared with every other snapshot that links to it.** Editing one in place changes it in all of them, so files are copied out, never opened and saved where they are. For the same reason Hive never uses rsync's `--inplace` or `--append`.
- **Layout:** `Hive/<server>/<job>/<date-time>/` on the drive, with each directory under `files/`, the dumps in `databases/`, and `manifest.json`. Server and job folders are named once, when created, from the name plus a short ID, and never renamed, so renaming in Beekeeper, two similar names, or a job re-added with an old name never share a folder.
- **In progress:** a run writes into `<date-time>.partial` and renames it when complete. The next run picks up a failed run's partial folder, so files already transferred aren't transferred again.
- **A missing or empty source folder fails the run,** instead of making an empty snapshot that looks like a success. A snapshot much smaller than the one before gets a warning (§13).
- **Database dumps** are streamed over SSH straight into the snapshot, never written as a file on the server. MySQL and MariaDB dumps are compressed with gzip. Postgres dumps use its custom format, which is already compressed. Dumps are stored whole on every run.
- **Manifests:** each snapshot's manifest gives the Hive ID, server and job, when it ran, what it holds, and whether it completed. Hive's catalog can be rebuilt from them (F3).
- **Snapshots aren't encrypted,** as with the PHP backups today. They hold database dumps, certificates' private keys and `.env` files, so anyone with the drive has them. An encrypted backup volume is later work (§18).
- **Owners and groups** are kept with rsync's `--fake-super`, as extended attributes on each file, because Hive runs as a normal user and can't set them.
- **Out of scope:** backing up the Hive Mac and its drive. Every Hive Mac should already have a full Mac backup, such as Arq, and the README says so.

## §10. Retention and quotas

- **Tiers:** each job keeps its newest snapshot from each of the newest N days that have one, and its newest from each of the last M months. Counting days that have a snapshot, rather than calendar days, means a long outage never ages out history. This replaces the PHP version's retention count and monthly copies. C6 settles the exact rules, with tests.
- **A quota for each server,** covering all its jobs' snapshots. Space is counted as it's used on the drive: a file hard-linked into several snapshots counts once.
- **When a server is over its quota,** Hive removes its oldest daily snapshots first until it fits. It never removes a monthly snapshot or the newest complete snapshot of any job to meet a quota. If that isn't enough, it emails (§13) and leaves the server over quota until you lower retention or raise the quota.
- **Lowering a quota or a job's tiers needs confirmation** (§6), since it deletes snapshots.
- **After a restore, retention and quotas wait** until you confirm in Beekeeper (F3). A drive restored from a Mac backup may have lost its hard links, and its space count would delete history.
- **Removal never touches anything outside the job's folder,** and never a folder being written.
- **Retention must never remove the wrong snapshot.** Every change to it adds tests (AGENTS.md).

## §11. Running backups

- **`ssh` and `rsync` run as child processes,** as in the PHP version, through `Runner` types (`Architecture/README.md`).
- **Hive bundles rsync 3.x,** built from source at a fixed version by a script, and signed and notarized inside `Hive.app`. macOS's `openrsync` exits with only 0, 1 or 2, so a file that vanished mid-run can't be told from a real failure, and it has no `--fake-super`. rsync is GPLv3, shipped as a separate program with its source available (I1).
- **Hive generates its own Ed25519 SSH keys,** stored as secrets (§7) and handed to `ssh` at run time, never written in plain text to `~/.ssh`. Beekeeper shows the public key to add to the server's `authorized_keys`, with a `from=` restriction to the Hive Mac's addresses offered.
- **Host keys** are recorded when a server is added, after you confirm the fingerprint in Beekeeper. Hive keeps its own `known_hosts` file and connects with `StrictHostKeyChecking=yes`. When a key changes, that server's backups fail and Hive emails right away, then daily until the new key is confirmed in Beekeeper or the original one comes back (§13).
- **Stalls end runs:** rsync's `--timeout` and SSH's `ServerAliveInterval`, so a hung transfer fails instead of blocking the queue.
- **Database containers are found by their Swarm or Compose service name,** and exactly one must match. Your servers run Docker Swarm, which names containers like `buzzingpixel_db.1.<id>`.
- **Database passwords never appear on a command line,** on either machine. The PHP version puts them there.
- **Scheduling:** each job runs at its times, in the Hive Mac's local time. If Hive was off or the Mac was asleep at a scheduled time, the job runs once when Hive is back. Hive warns when the Mac is set to sleep. Jobs run one at a time from a queue kept in the store, so it survives restarts. Beekeeper can start and cancel runs.

## §12. Logs

As AGENTS.md describes:

- **The job log** is Hive's record of what each run did: which job, each directory and database, how long it took, how much it transferred, and what failed and why. Beekeeper shows it.
- **The audit log** records every change made through the API, which device made it and when, never the value of a secret. Beekeeper shows it.
- **The system log** is for debugging, and never holds hostnames, paths or other private details.

## §13. Email and alerts

- **SMTP with your own provider:** host, port, STARTTLS or implicit TLS, username and password (write-only), and one or more recipients. A "send test email" action.
- **Alerts:**
  - a backup failed, including lost Full Disk Access
  - the backup drive is missing, as one email, not one for each job
  - a job is overdue: no complete snapshot for longer than its schedule allows
  - a snapshot much smaller than the one before (§9)
  - a server's host key changed, with the old and new fingerprints and the last successful backup, repeated daily until resolved
  - a server is over its quota with only monthly and newest snapshots left (§10)
  - the backup drive is filling up, or the quotas add up to more than it holds
  - an iPhone or iPad build is about to expire (§16)
- **A job that keeps failing** emails on the first failure, then once a day, and once more when it succeeds again. Email is never sent once per failed run.

## §14. Recovery

Read the brainstorm's "Recovery files and disaster recovery".

- **A recovery key is created at setup** and shown once, to save in a password manager or print. Setup can't finish until part of it is entered back. Hive keeps only the public half, so it can encrypt recovery files but never decrypt them (HPKE).
- **Recovery files** hold the whole configuration and every secret, including the Hive ID. They're written on a schedule and whenever the configuration changes.
- **Copies:** in Hive's data directory, which the Mac backup picks up; on every paired Beekeeper; and on the Mac, optionally in a folder you choose, such as one in iCloud Drive. Every copy is safe to keep anywhere as long as the recovery key is safe.
- **A new recovery key** can be made from Beekeeper while the Hive exists, and new recovery files use it. Older files still open with the old key, and copies of them stay in Mac backups. So Beekeeper deletes the old copies it manages, and when the old key may have leaked, Hive suggests rotating SSH keys and changing credentials.
- **Restoring on a new Mac:** install Hive and Beekeeper, which pairs itself; restore the backup drive from the Mac backup if needed; choose Restore from Recovery File and enter the key; then choose the backup drive again, since a restored drive has a new volume UUID. Hive encrypts every secret again for the new Secure Enclave, keeps the same Hive ID, and takes over the snapshots on the drive through their manifests. Other devices see the same Hive ID with a new key, and Beekeeper says "This Hive's identity has changed, pair again". It never accepts the new key silently.
- **Rotating SSH keys** after a restore is optional, and one action: Hive installs a new key on each server with the old one, then removes the old one.
- **Without the recovery key,** you start over: new SSH keys to add to each server, every credential entered again, and snapshots still taken over through their manifests.

## §15. Beekeeper

- **A list of Hives** and, for each: servers and backup jobs, their status and live progress, snapshots and their sizes, the job log, the audit log, devices, and the Hive's settings.
- **Connected to several Hives at once,** so it can show all their status.
- **Addresses:** typed in, or taken from a pairing code. Several address options per Hive, using whichever responds. Hive advertises itself with Bonjour on any LAN interface it listens on, with a setting to turn it off (H2).
- **On the Hive Mac** it pairs itself (§6).
- **A proper Mac app,** with menus, keyboard handling, and windows that remember their size and place. The layout is worked out together in Phases B and D.

## §16. Build expiry warnings

Read the brainstorm's "Warnings before an iOS build expires".

- **iPhone and iPad builds expire:** TestFlight builds after 90 days, ad hoc builds when their provisioning profile does. The Mac apps never expire.
- **Beekeeper works out its own expiry date:** for ad hoc builds, `ExpirationDate` in `embedded.mobileprovision`; for TestFlight, the build date stamped into `Info.plist` by the release script, plus 90 days.
- **It reports its build details at sign-in:** platform, device name, version, build, how it was distributed, and when it expires.
- **Hive checks once a day** and emails 14 days before, then 3 days before, once per build. A new build resets the warnings. Expired builds are marked in the device list. Each Hive has a setting to turn these off, so only one Hive needs to send them.
- **Known limitation:** Hive only knows the build a device last reported, so a new build that hasn't been opened yet can get a stale warning.

## §17. Open source

- **The team ID and bundle ID prefix** live in a gitignored `.xcconfig`, with a template checked in.
- **The README** covers building it, that builds from free Apple accounts expire after 7 days, Full Disk Access, auto-login and the FileVault limitation (§4), the case-sensitive drive and copying files out of snapshots (§9), and that every Hive Mac needs its own full Mac backup.
- **Signed builds of both Mac apps** are published.
- **The license:** see §19.

## §18. Later phases

Each gets its own plan once this one is done. Until then, features not in Part 1 go here.

- **Server stats:** Hive collects stats from each server, such as disk, memory and load, and alerts when one is outside the range set for it.
- **Heartbeats:** a server, or a job on it, checks in on a schedule, and Hive alerts when a check-in is late. Needs a way for servers to reach Hive that fits §5.
- **HTTP status checks:** Hive requests URLs on a schedule and alerts when one fails or answers with an unexpected status.
- **Restore from Beekeeper:** send a snapshot's files or a database dump back to a server, behind the extra confirmation for destructive actions (§6).
- **Relinking after a restore:** when a backup drive comes back from a Mac backup without its hard links, Hive links identical files across snapshots again to recover the space.
- **Running with nobody logged in on your Hive Mac:** Tailscale as the `tailscaled` system service, and external drives mounted at boot.
- **An encrypted backup volume** that Hive unlocks at boot.
- **Grouping servers,** if a flat list of servers gets long.

## §19. Open questions

- [ ] Do CryptoKit's Secure Enclave keys work from the daemon after it switches user, outside any login session? (A4) Everything in §7 depends on it.
- [x] Channel binding: dropped. SwiftNIO's TLS doesn't expose the TLS exporter (its BoringSSL has one, but not publicly), and `URLSession` doesn't either. Keeping it would mean forking the server's TLS and writing Beekeeper's own HTTP client (§6).
- [ ] Where Beekeeper keeps its device keys on the Mac, so that other programs running as you can't use them (B2)
- [ ] The default port (B1)
- [ ] How Hive hands decrypted SSH keys to `ssh`: a short-lived file in a `0700` folder, deleted right after use, or an `ssh-agent` run by Hive (C2)
- [ ] One SSH key per server, or one for the whole Hive (C2)
- [x] Bundling rsync: yes, rsync 3.x, for its exit codes and `--fake-super` (§11)
- [x] Owners and groups of backed-up files: kept with rsync's `--fake-super` (§9)
- [ ] How long the job log is kept (C5)
- [ ] Default retention tiers and quota (C6)
- [ ] An SMTP library, or a small client of Hive's own over SwiftNIO (E1)
- [ ] How Hive updates itself (G2). `Hive.app` isn't running most of the time, and the daemon has to restart from the new bundle.
- [ ] The license (I1). The other open-source Locus apps use MIT.

---

# Part 2 — How the work is done

## Slices

- **Files are numbered in the order the work happens.** A slice added later is numbered into its place, and the files after it move along, links included. The checklist groups slices by phase; the numbers give the order across phases.
- **One slice per session.** Each slice is sized so a session has plenty of room in an Opus 5.5 1M-token context after reading this file, the slice's file and the code it touches, including for going back and forth to adjust things. A few slices say "2 sessions" or "1–2 sessions". Split those wherever a natural break shows up.
- **Each slice has a kind:**
  - **Engine:** mostly code and tests, little back-and-forth needed.
  - **UI:** built with you. Expect to spend time adjusting the look and behavior together.
  - **Mixed:** an engine part first, then a UI part.
- **Each slice has a "done when".** A slice isn't finished until that's true. Before Phase D's screens exist, Phase C's checks go through Beekeeper's Developer window (B3).
- **"Installed build"** means the slice touches the daemon's registration, a permission, an entitlement, code signing or the Secure Enclave, and is checked in a copy installed with `Scripts/install-test-build.sh --mac-installed`, never a build run from Xcode or Terminal (AGENTS.md). **"TestFlight"** means it has to be checked on a real iPhone or iPad. **"Needs you"** means steps only you can take, such as approving in System Settings, restarting the Mac, or working in your Apple Developer account.
- **Order is flexible where dependencies allow.**

## Reusing the other projects

Code is copied and adapted, not shared through a package. Each slice names what to look at. The main sources:

- **Locus Write** (`../locus-write`) and **Locus Calendar** (`../locus-calendar`):
  - this plan's format
  - `Scripts/build-and-test.sh`, `Scripts/install-test-build.sh`, `Scripts/TestBuildExportOptions.plist` and the `TEST_BUILD` flag
  - `.swiftlint.yml` and its rule keeping UI frameworks out of the core
  - `Plans/HighLevelPlan/TestFlightChecks.md`
- **Locus Calendar:** the multiplatform app target, and the iOS release script and first TestFlight build (`Scripts/release.sh`, `Plans/HighLevelPlan/05-A5-ReleaseScriptAndFirstTestFlightBuild.md`)
- **Locus Git Gui** (`../locus-git-gui`) and **Locus Launcher** (`../locus-launcher`):
  - Developer ID releases with notarization and Sparkle (`Scripts/release.sh`, `Scripts/sparkle-tools.sh`, `Scripts/README.md`, `docs/appcast.xml`)
  - running command-line tools as child processes (Git Gui's `GitRunner/`)
- **site-backups** (`../site-backups`): the configuration model, the rsync and dump commands (`src/Backup`), its Docker setup (`docker/docker-compose.prod.yml`), and what to fix during the port (§11)

## Development servers and drives

- **A test server in Docker,** from C2 on: `sshd` with the same rsync version as your real servers, MariaDB, MySQL and Postgres running as Swarm services so their containers are named as on your servers, sample data, and sample files, some of which change between runs. It lives in the repository and is started by a script. Development backs it up, never a real server.
- **A test backup drive,** from C3 on: a case-sensitive APFS disk image mounted on the development Mac. Ejecting it is how the missing-drive case is checked.
- **Tests use neither.** They run against temporary folders and fakes. They may run `rsync` between local temporary folders, never `ssh`.

## Every slice ends with

- `Scripts/build-and-test.sh` passing: Hive for macOS, Beekeeper for macOS and iOS, and both packages, with zero warnings, SwiftLint included, and every test passing
- The installed-build checks done, when the slice has them
- A self-check against `Architecture/README.md` and `Architecture/ReviewChecklist.md`
- The slice checked off in the checklist above, with any follow-ups added to the slice files or sections they belong in
- From Phase H on, anything that needs a real iPhone or iPad added to [TestFlightChecks.md](TestFlightChecks.md)

## Rules for every slice

- **AGENTS.md's security rules hold in every slice,** Debug builds and temporary code included. No bypass "just for testing".
- **Never back up from, restore to, or remove anything on a real server or the real backup drive while developing.** Use the test server and the test drive. Never touch `site-backups` before G3.
- **Every change made through the API goes in the audit log,** from B3 on.
- **HiveKit holds the wire contract only.** Hive's logic goes in HiveCore (§3).
- **Features not in Part 1 go in §18** until you decide otherwise.
