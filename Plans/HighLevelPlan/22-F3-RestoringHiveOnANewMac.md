# F3. Restoring Hive on a new Mac

**Phase F — Recovery** · Mixed, 2 sessions, installed build, needs you

References like §14 point to [00-Info.md](00-Info.md). Read the brainstorm's "Recovery after the Hive Mac is lost" and "Manifests: backup sets that describe themselves".

## Engine

- **Restoring from a recovery file,** only on a Hive with no configuration yet: Beekeeper on the Hive Mac sends the file and the recovery key over its local connection. Hive decrypts the file, encrypts every secret again for its own Secure Enclave, keeps the Hive ID, and forgets the key.
- **Choosing the backup drive again** (§14), since a restored drive has a new volume UUID. Hive checks its `Hive/` marker carries the same Hive ID. C3's `PUT /backup-drive` already accepts a drive marked with this Hive's ID and refuses another Hive's. The marker is `Hive/.hive-drive.json`, and each snapshot's `manifest.json` is C3's `SnapshotManifest`, format 1.
- **Rebuilding the catalog from manifests** (§9): Hive scans the drive's `Hive/` folder and takes over every snapshot whose manifest carries its Hive ID. This also works when Hive's store is lost.
- **Retention and quotas wait** until you confirm in Beekeeper (§10). A drive restored from a Mac backup may have lost its hard links. C6 honors `hive.retentionPausedSince`: set it when restoring, and clear it, audited, when a device starts retention again. While it's set Hive still counts space, which the summary can show. Catalog entries rebuilt from manifests start uncounted, and the first pass counts each job whole.
- **Rotating SSH keys** (needs confirmation, §6): for each server, Hive adds a new key to `authorized_keys` using the old one, checks the new one works, then removes exactly the old key's line. A server that fails keeps its old key and is reported. C2's `POST /servers/<id>/ssh-key` replaces the stored key at once, so rotation has to hold the new key beside the old one until the new one is checked.

## UI

Built with you:

- **Restore from Recovery File** in setup on a new Hive, beside starting fresh
- **After a restore,** a summary: servers, jobs and snapshots taken over, the space they use against each quota, and a button to start retention and quotas again
- **Rotate SSH Keys** in the Hive's settings, with each server's result

## Tests

- Restoring gives the same configuration and secrets, with a new storage key
- The catalog rebuilt from manifests matches the one it replaces, and skips snapshots from another Hive
- Retention and quotas remove nothing after a restore until confirmed
- Rotation never removes the old key from a server where the new one didn't work

## Checking it

With a second Mac if one's available. Otherwise, remove Hive from this Mac completely, including its data directory, reinstall, and restore. Back up and remove only from the test server and the test drive.

- **From D4:** a confirmed route reads its request with `ConfirmedRequest.read` and checks `ConfirmationRequirement.check` inside the store's write transaction, against the stored values. Add the new `ConfirmationReason` to HiveKit, its Touch ID wording to `ConfirmationReason.prompt`, and a case to `ConfirmedRouteTests.cases`, which covers the refusals. In Beekeeper, send it with `HiveLink.confirmed(_:_:body:reason:)`, giving a `reason` when the change is known to need confirming.
- **From D4:** `POST /servers/<id>/ssh-key` already refuses to replace a key without confirmation, so rotation's own route needs its own `ConfirmationReason`.

**Done when:** a restored Hive has the same Hive ID, configuration and snapshots, and backs up the test server without any key being added to it; nothing is removed until retention is started again; the old Beekeeper key is refused and Beekeeper says the identity changed; rotating SSH keys leaves the test server with only the new key; and the tests pass.
- **From F1:** `RecoveryFile.open(_:with:)` takes `RecoveryKey(code:).privateKey`, and throws `otherKey` for a file written for another key and `couldNotOpen` for one that was altered. `RecoveryContents` follows the store's columns, with secrets opened: seal each again with `SecretSealer` as it goes back. Restoring writes the store's `hive.id`, which `HiveAPI.hiveID` is read from at start.
- **From F2:** every Beekeeper keeps each Hive's latest recovery file at `Recovery Files/<Hive ID>.hiverecovery` in its Application Support folder, and on the Mac possibly another in a chosen folder, named after the Hive. HiveKit's `RecoveryFileHeader.publicKey(of:)` reads which key a file was written for, so Beekeeper can check the entered key matches before sending the file. New Recovery Key's wording suggests giving each server a new SSH key and changing passwords, since Rotate SSH Keys doesn't exist yet: point it at Rotate SSH Keys once it does.

## How it was built

- **Restoring** is `POST /restore` with a `RestoreRequest`: the file and the recovery key as typed. `RestoreWorkflow` takes it only over loopback (`RestoreRoutes.isLoopback`), so the recovery key never crosses a network, and only while `RecoveryContentsWriter.isUnconfigured`: no servers, email, recovery key, backup drive or snapshots. It isn't confirmed with Touch ID: it needs the recovery key itself, and can't overwrite anything. Every secret is sealed again with `SecretSealer`, the store takes the file's Hive ID, settings, servers, jobs, email and the recovery key's public half (so recovery files go on using the same key), and `retentionPausedSince` is set. Devices and logs stay, so Beekeeper on this Mac goes on signing in. Then Hive restarts, since everything it started with carries the old ID.
- **Beekeeper** offers Restore from a Recovery File in a new Hive's setup (`HiveSetupSheet`) and beside Set Up Recovery Key, only on the Hive's Mac while `RestoreState.canRestore`. `RestoreSheet` lists the copies Beekeeper keeps (F2) and takes any other file, and checks the key against the file's header before sending. Afterwards `HiveListStore.adoptRestoredHive` files this device's key under the restored Hive's ID, replaces any older entry for it, and `HiveLink.reconnectAfterRestart` waits for Hive to go and come back before signing in, so it never counts as a failed sign-in.
- **Taking over snapshots** is `SnapshotCatalogBuilder`: it reads each snapshot folder's manifest (`O_NOFOLLOW`, size-limited, real folders only), takes those with this Hive's ID, and moves any it already had on another drive. It runs after a restore when the drive is mounted, and whenever a drive is chosen, so a drive restored from a Mac backup with a new UUID is taken over by choosing it. Taking anything over sets `retentionPausedSince`, so retention waits after a drive restore too, and the counts start empty, so the first pass counts each job whole.
- **Retention waits** until `DELETE /retention-pause`, confirmed (`ConfirmationReason.retentionStarted`) and audited. Meanwhile passes count but remove nothing, and `GET /restore` gives each server's space against its quota and each job's snapshots, which the overview shows (`RetentionPausedSection`).
- **Rotating SSH keys** is `POST /ssh-keys/rotation`, confirmed (`.sshKeysRotated`). It answers at once, and `SSHKeyRotationWorkflow` runs while holding the job queue (`BackupRunCoordinator.whileHeld`), since a run loads its server's key once. For each server, alongside the others: read `~/.ssh/authorized_keys` with the old key, add a line for the new key with the old line's options (`AuthorizedKeysScript`, POSIX `sh`, lines passed as arguments), connect with the new key, keep it (audited as `.sshKeyRotated`), then remove exactly the old lines over a connection made with the new key. A server that turns the new key down keeps its old key, and the new line is taken out again. Results are kept in memory and shown in Settings › SSH Keys. `DumpCommand`'s quoting moved to `RemoteCommandLine` for it.

## Checked so far

On the development daemon with Debug Beekeeper, the test server and the C4 test drive (2026-11-10): a recovery file of the development Hive, with its real secrets and a new recovery key, restored onto a wiped development Hive. The old entry showed "This Hive's Identity Has Changed"; the setup sheet offered the restore; a mistyped key was caught; the Hive came back with the same ID, settings, email, server and four jobs, took over the drive's 20 snapshots, restarted, and Beekeeper signed in again; retention counted and removed nothing; and Example site backed up the test server with the restored SSH key and database password, nothing added to the server, hard-linked against the snapshots taken over. The rotation scripts ran under the test server's own `dash`.

Then, by you: Start Retention and Quotas and Rotate SSH Keys on the restored development Hive, rotation leaving the test server with only the new key.

In the installed builds (2026-11-11): Hive removed in Hive.app, its data folder moved aside and its recorded user reset, then turned on again, approved, and restored from Beekeeper's copy. It came back with its 2 servers and 2 jobs, took over the drive's 8 snapshots, kept Full Disk Access, and Beekeeper signed in again by itself. Retention counted and removed nothing; Run Now backed up with the restored keys; and once retention was started, it removed 2 snapshots.

Left open:

- **From F3:** §14's "without the recovery key … snapshots still taken over through their manifests" isn't built. A new Hive turns down a drive marked with another Hive's ID, so taking over without a recovery file needs a way to adopt that drive, decided with you.
- **From F3:** Pair Again on a Hive whose ID has changed, such as a wiped Hive, adds the new Hive to the list but leaves the old entry selected. If that Hive is then set up new rather than restored, the old entry can't be removed, since an identity-changed entry offers no Remove from Beekeeper.

