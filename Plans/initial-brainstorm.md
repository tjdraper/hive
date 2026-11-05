# Hive: Connection and Security Design

## Context

- **Hive**: the main app. It runs on one dedicated Mac, which is the only platform it supports. It replaces `site-backups` (SSH, rsync, MySQL/Postgres dumps, retention, monthly snapshots, scheduler/queue) and will gain more features over time.
- **Hive Beekeeper**: the management app for iPhone, iPad and Mac. It is the **only interface to Hive**. Hive has no settings window or menu bar app of its own. Its app bundle exists only to install and register the background service. One Beekeeper can manage **several Hives**.
- The project will be open source.
- **Distribution:**
  - Hive and the Mac version of Beekeeper ship with Developer ID and notarization, plus Sparkle for updates. They are not on the App Store, which also avoids the App Sandbox.
  - Beekeeper for iOS/iPadOS goes on the author's devices through internal TestFlight builds, or ad hoc builds as a fallback. Other people build their own.
- **Notes for open source:**
  - Keep the team ID and bundle ID prefix in a gitignored `.xcconfig`, with a template checked in.
  - Note in the README that builds from free Apple accounts expire after 7 days.
  - Publish signed builds of both Mac apps.
  - The iOS app needs `NSLocalNetworkUsageDescription` and `NSBonjourServices` for Bonjour discovery.

## Guiding principle

Hive gives the network no trust at all. It is mainly used over a tailnet, but it must be just as safe when someone exposes it on a port on the public internet. The tailnet is treated exactly like the open internet.

## Encryption: always TLS

- **No plain HTTP mode at all.** The tailnet already encrypts traffic, but an unencrypted setting is precisely what someone would later turn on for internet exposure.
- **One certificate mode: self-signed and fully managed by Hive.** There's no option for a user-supplied or public certificate, and no support for a reverse proxy that ends TLS before it reaches Hive.
  - On first launch, Hive creates a P-256 key **in the Secure Enclave**, then makes a self-signed certificate for it with `swift-certificates`.
  - SwiftNIO's TLS sends its signing operations to the Secure Enclave through `NIOSSLCustomPrivateKey`, so the TLS private key never exists as a file. See "Secrets and keys at rest".
  - Beekeeper **pins the public key**, not the whole certificate. Hive can then reissue the certificate with the same key without breaking any paired device.
  - Beekeeper checks the certificate itself, through its own trust evaluation. It compares the public key's hash to the pinned value and ignores the certificate chain, the hostname and the expiry date. The certificate is given a long validity period (10 years) anyway.
  - Hive has a "regenerate identity" action that creates a new key, for example if the old one may be compromised. Every device has to pair again afterwards.
- **Exposing Hive to the internet:** forward the port directly, or use any tunnel that passes TCP through without decrypting it. TLS always ends at Hive.
- **Configurable listen address and port.** A single setting covers localhost only, a specific interface (for example the Tailscale one) or all interfaces.

## Authentication: a key per device, with no passwords

- **The first device: Beekeeper on the Hive Mac pairs itself automatically.**
  - It connects to Hive over a local XPC service, which can't be reached over the network.
  - Hive checks the connecting app's code signature using its audit token. The app must be signed by the **same team ID as Hive itself** and have Beekeeper's bundle ID. Other processes on the Mac can't pass this check. Because the team ID is compared with Hive's own, there's nothing hard-coded, and open-source builds signed with someone else's team ID work too.
  - Once the check passes, Hive registers the device's key with no code to enter.
  - **XPC is used only for this pairing step.** After that, Beekeeper on the Hive Mac uses the same HTTPS API on `127.0.0.1` as every other device. There's only one API to build and secure.
  - Being on the same Mac never skips authentication. An unauthenticated port on localhost could be used by any process on the Mac, and possibly by web pages through DNS rebinding.
- **More devices: any paired Beekeeper can open a pairing window.**
  - The window shows a QR code or short code that is single-use and expires in about 5 minutes.
  - The code contains:
    - the Hive's unique ID
    - the address options (LAN, MagicDNS, public hostname)
    - the hash of Hive's public key, for pinning
    - a one-time pairing token
  - Every device has full access, so letting a paired device start pairing gives it nothing it doesn't already have. A new device can only be added with the help of one that's already paired, and the very first device always has to be on the Hive Mac.
- **Each Beekeeper device creates a P-256 key in the Secure Enclave**, so the private key can never leave the device. During pairing, Hive records the public key and a device name. Every paired device has full access, and there are no roles.
- **Login works by challenge and response.** Beekeeper signs a fresh challenge from Hive and gets back a short-lived session token. The token is used for HTTP requests and the WebSocket.
- **Why not mutual TLS (client certificates):** it is awkward to combine with Secure Enclave keys on Apple's networking stack.
- **Replay protection:** every challenge carries a nonce and an expiry. Because TLS always ends at Hive, the signature is also always tied to that specific TLS connection (channel binding through a TLS exporter). A signature captured on one connection can't be used on another.

## Hardening for internet exposure

- **Unauthenticated requests reach almost nothing.** Only these respond:
  - the challenge endpoint
  - the pairing endpoint, which only accepts requests while the pairing window is open
  - a minimal health check

  Everything else is refused before any routing or parsing.
- **Rate limiting and lockout** for failed attempts on authentication and pairing.
- **Extra confirmation for destructive actions** (restore, delete backups, change server credentials): these need a second Secure Enclave key protected by `.userPresence`, so the user has to pass Face ID or Touch ID even if the session is already open.
- **Secrets are write-only through the API.** Beekeeper can set SSH keys and database passwords but can never read them back, so a compromised client can't pull credentials out of Hive.
- **Device management:** Beekeeper shows each paired device and when it was last seen, and can revoke any device instantly.
- **Audit log:** every change made through the API is recorded.

## Protocol and server

- **HTTPS with JSON** for commands, plus a **WebSocket** for live job progress and logs. Both work over direct connections, port forwarding and tunnels that pass TCP straight through.
- **Server:** Hummingbird 2, built on SwiftNIO, gives Hive TLS, routing and WebSockets without Vapor's weight.
- **Shared code:** a `HiveKit` Swift package holds the API types and the client used by all three Beekeeper platforms.
- **Finding Hive:**
  - Bonjour discovery on the LAN is optional, and an address can always be typed in manually.
  - Beekeeper stores several address options per Hive and uses whichever one responds.

## Managing several Hives

- Beekeeper keeps a list of Hives. Each one is identified by its unique ID and stores:
  - a display name
  - its address options
  - its pinned public key hash
- **Beekeeper uses a separate Secure Enclave key for each Hive.** Removing a device from one Hive doesn't affect the others, and two Hives can't tell that the same device is paired with both.
- Beekeeper can stay connected to several Hives at once, so it can show the status of all of them.
- Pairing with a second Hive works the same way as with the first, using a pairing code from that Hive. The first device paired with that Hive must be Beekeeper on its own Mac.

## Warnings before an iOS build expires

Builds of Beekeeper for iPhone and iPad expire: TestFlight builds after 90 days, ad hoc builds when their provisioning profile expires. The Mac apps are signed with Developer ID and never expire.

1. **Beekeeper works out its own expiry date:**
   - **Ad hoc:** it reads `ExpirationDate` from `embedded.mobileprovision` in the app bundle. That file is a signed plist: pull out the `<?xml … </plist>` part and parse it with `PropertyListSerialization`.
   - **TestFlight:** the build script stamps the build date into `Info.plist`, and the expiry is that date plus 90 days. This is a little early, because the build is uploaded after it's made, which is the safe direction. To tell a TestFlight install from an ad hoc one, check for the provisioning file: if it's missing, the app is either a TestFlight or an App Store install.
2. **Beekeeper reports its build details to Hive** each time it starts a session (during the challenge-and-response step):
   - platform and device name
   - app version and build number
   - how it was distributed (TestFlight, ad hoc or Developer ID)
   - when the build expires

   Hive stores these for each paired device. The iOS app shows no expiry notifications of its own.
3. **Hive checks once a day and sends an email:**
   - A warning goes out **14 days before** a build expires, and a final one at **3 days**.
   - Each warning is sent only once per build. A new build number resets them.
   - If a device's build has already expired, Hive's device list marks it as expired.
4. **With several Hives:** every Hive a device connects to would send its own warning email. Each Hive has a setting to turn off build expiry warnings, so they can be left on for just one Hive.
5. **Known limitation:** Hive only knows about the build a device last reported. If a new build is installed but Beekeeper isn't opened on that device, Hive can send a stale warning. It clears the next time that device connects.

## Email

Hive has email built in. It's used for build expiry warnings, SSH host key changes, backup failures and, in future, quota alerts.

- Mail is sent over SMTP using the user's own provider and settings (host, port, STARTTLS or implicit TLS, username, password).
- The SMTP password follows the same write-only rule as other secrets.
- Settings include a "send test email" action.

## How Hive runs

- **As a LaunchDaemon**, registered with `SMAppService.daemon` from the Hive app bundle. The user approves it once in System Settings → General → Login Items.
- **It starts at boot without anyone logged in**, and Beekeeper on the Hive Mac is its interface. The daemon also provides the XPC service used for local pairing.
- **It doesn't need auto-login, and it works whether FileVault is on or off.** With FileVault off, Hive starts at boot after a power cut. Auto-login isn't needed for Hive and can be turned off unless something else on the Mac requires it.
- **Full Disk Access:** a daemon can't show permission prompts. Grant Full Disk Access to Hive's binary once during setup so it can write to external and network backup volumes.
- **Documented limitation for FileVault users:** after an unexpected restart, the Mac waits at the FileVault unlock screen, and Hive doesn't run until someone unlocks the disk. For planned restarts, `fdesetup authrestart` avoids this. Beekeeper only sees that Hive is offline; it can't tell why.

### Which account the daemon runs as

**The daemon runs as the user who installed Hive** (normally the Mac's main account), never as root once it has started.

- **Why the account can't simply be set in the daemon's configuration file:** an `SMAppService` daemon's launchd plist ships inside the signed app bundle, so it can't include a `UserName` that differs from Mac to Mac.
- **How it works instead:**
  1. launchd starts the daemon as root.
  2. On its very first start, which happens right after the user approves it in Login Items, the daemon records who that user is (the user logged in at the Mac's screen). It saves this in a root-owned file under `/Library/Application Support/Hive/`.
  3. On every start, the daemon reads that file, then immediately and permanently gives up root and runs as that user (`initgroups`, `setgid`, `setuid`). It confirms root can't be regained before doing anything else.
  4. As little as possible happens while the daemon is root: reading one file and switching user. It doesn't open the network listener, create Secure Enclave keys or read secrets until after the switch.
- **Data directory:** `~/Library/Application Support/Hive/` in that user's home folder, so the regular Mac backup includes it.
- **Changing the account later:** a reset command run locally on the Hive Mac, which requires an administrator password. It's rarely needed and isn't available from a remote Beekeeper.
- **Add to the Secure Enclave prototype:** confirm that Secure Enclave keys work for a process that started as root and switched to a normal user, outside any login session.

## Secrets and keys at rest

Hive can't rely on FileVault, because many Hive Macs run without it so they can start up unattended. A daemon also has no login keychain. Instead, Hive protects everything with the Secure Enclave.

- **The keys:**
  - **Identity key (P-256 signing):** used for TLS. Its private key never exists in a usable form outside the Secure Enclave.
  - **Storage key (P-256 key agreement):** used to protect secrets.
- **Storage:** CryptoKit's Secure Enclave keys have a `dataRepresentation`, an encrypted blob that only this Mac's Secure Enclave can use. Hive stores these blobs as ordinary `0600` files in its data directory. The keychain isn't needed.
- **How secrets are encrypted:**
  - Covers SSH keys, database passwords, the SMTP password and any future credentials.
  - For each secret, Hive creates a temporary key and does an ECDH exchange with the storage key. HKDF turns the result into an AES-GCM key, which encrypts the secret.
  - Only the encrypted result is written to disk. Secrets are decrypted only in memory, when they're needed.
- **What this protects against:** a copy of Hive's data directory is useless on any other machine, whether it's a Mac backup, a disk image, a clone or a copy made by mistake. Restoring Hive goes through a recovery file (see "Recovery files and disaster recovery"). This doesn't depend on FileVault, the keychain or anyone being logged in.
- **What it doesn't protect against:**
  - Code running as Hive's user on the same Mac can still use the Secure Enclave keys, just as it could use the keychain. File permissions and the daemon's user account handle this risk.
  - Physical access to a Mac with auto-login on and FileVault off. No design can protect against that.
- **Hardware:** this needs Apple silicon or a T2 Mac. On older Intel Macs, Hive falls back to unencrypted `0600` files and shows a clear warning in Beekeeper.
- **Check first:** confirm that CryptoKit's Secure Enclave keys work from a LaunchDaemon with no user session, using a small prototype, before building on this design.

## Recovery files and disaster recovery

The Secure Enclave keys only work on the Mac that created them. If that Mac is lost or destroyed, everything they protect goes with it. Hive therefore writes **recovery files** automatically. Moving Hive to a new Mac uses the same mechanism; there's no separate export feature.

### Scope

Backing up the Hive Mac and its attached drives is **outside Hive's scope**. Every Hive Mac should already have a full Mac backup, for example Arq with a Hetzner Storage Box, and the README says so. Hive doesn't copy its backup data to other locations.

Restoring Hive's data directory from that Mac backup onto a new Mac does **not** restore Hive, because the secrets in it can only be decrypted by the old Mac's Secure Enclave. Restoring Hive always goes through a recovery file.

### The recovery key

- **Created at setup:** Hive generates a recovery key and shows it once, as a code to save in a password manager or print. Setup can't finish until the user confirms the key by entering part of it back.
- **Hive keeps only the public half.** It can encrypt recovery files but can't decrypt them. Encryption uses HPKE (Hybrid Public Key Encryption) from CryptoKit.
- **Losing the recovery key:** an export stays possible as long as the original Hive still exists. From Beekeeper, the user can create a new recovery key; Hive writes a new recovery file with it, and every older file stops being usable.

### Recovery files

- **Contents:** the whole configuration and every secret, including the Hive's unique ID, servers, schedules, SSH keys, database credentials and the SMTP settings.
- **When they're written:** on a schedule, and whenever the configuration changes.
- **Where copies go:**
  - **Hive's data directory**, so the regular Mac backup picks the file up automatically. That makes the Mac backup the main off-site copy.
  - **Every paired Beekeeper** keeps the latest recovery file. On the Mac, Beekeeper can optionally keep its copy in iCloud Drive.
- **These copies are safe to keep anywhere**, because none of them can be decrypted without the recovery key.

### Recovery after the Hive Mac is lost

1. Install Hive and Beekeeper on a new Mac. Beekeeper pairs itself automatically.
2. **Restore any backup drives first** from the Mac backup, if they're needed.
3. In Beekeeper, choose **Restore from recovery file**. Use the copy from any paired device, from iCloud Drive or from the Mac backup, and enter the recovery key.
4. Hive decrypts the file, encrypts every secret again with the new Mac's Secure Enclave, and keeps the same Hive ID.
   - Hive's SSH keys come back too, so there's no need to update `authorized_keys` on every server.
5. Hive scans its backup drives and takes over existing backup sets using their manifests (see below).
6. **Other devices pair again.** They recognize the Hive ID but see a new TLS key. Beekeeper shows "This Hive's identity has changed, pair again" and **never accepts the new key silently**, because an unexpected key change is exactly what an attack looks like.
7. **Rotate SSH keys** (optional; recommended if the old Mac may have been stolen rather than destroyed):
   - Hive can still reach each server with the old key. It installs a new key and removes the old one, in one action.
   - Database passwords and other credentials have to be changed by the user.

Moving to a new Mac on purpose follows the same steps. Rotating SSH keys isn't needed there.

### Manifests: backup sets that describe themselves

Each backup set stores a manifest next to its data, giving its source, date, type and retention details. Hive's database then isn't the only record of what's in a backup. After a restore, or if Hive's database is lost, Hive rebuilds its catalog from what's on the drives.

### Without the recovery key

The user starts over:

1. Hive generates new SSH keys, and the user adds them to every server.
2. The user enters every credential again.
3. Existing backup sets on the drives can still be taken over through their manifests.

The design can't do better without weakening its security. That's why setup makes saving the recovery key impossible to skip.

## Porting site-backups

Everything in `site-backups` is being ported to Swift. The PHP version keeps running until Hive takes over.

- **What gets ported:**
  - backing up directories with rsync over SSH (`--archive --delete`)
  - remote MySQL and Postgres dumps, run over SSH
  - retention
  - monthly snapshots
  - scheduling and the job queue
- **Approach:** Hive runs the system `ssh` and `rsync` as child processes, as the PHP version does. This avoids building an SSH or rsync implementation into Hive.
- **rsync:** macOS now includes `openrsync` (compatible with rsync 2.6.9) instead of GNU rsync. The flags in use (`--archive`, `--delete`) work with it. If more advanced flags are needed later, Hive can bundle a modern rsync.
- **Fixes during the port:**
  - **SSH host keys:** the PHP version uses `StrictHostKeyChecking=no`, which accepts any host key. Hive records each server's host key when the server is added, after the user confirms it in Beekeeper. It keeps its own `known_hosts` file and refuses to connect if a key changes. A changed key needs an explicit confirmation in Beekeeper.
    - **Email alert:** when a host key changes, that server's backup fails and Hive emails right away. The email names the server, the old and new key fingerprints, and when the last successful backup ran. Hive sends a reminder each day until the change is confirmed or the server's original key comes back, so a server never goes without backups unnoticed.
  - **SSH keys:** the PHP version uses one shared `/root/.ssh/id_rsa`. Hive generates its own Ed25519 keys, protected by the Secure Enclave, and gives them to `ssh` at run time. They're never written in plain text to `~/.ssh`.
  - **Configuration:** the PHP version keeps its configuration in code. In Hive it becomes data that is edited through Beekeeper. The PHP configuration model is a starting point, not a rule.

## Ideas to explore later

- **Incremental backups with a storage quota**, to replace the current approach of copying everything every time and then deleting older backups by retention rules.
  - Each backup stores only what has changed.
  - Each server or backup set gets a quota. When it's reached, the oldest backups are removed first.
  - If even the newest backup can't fit within the quota, Hive sends an email alert instead of skipping the backup without saying so.
  - Not designed yet. Possible approaches include rsync snapshots built with hard links (`--link-dest`; check whether `openrsync` supports it) and deduplicated storage split into chunks. The design needs to work with the manifests described under "Manifests: backup sets that describe themselves".

## Open questions

- **How Hive gives decrypted SSH keys to `ssh`:** options are a short-lived file in a `0700` directory that's deleted right after use, or an `ssh-agent` run by Hive. Decide during the port.
