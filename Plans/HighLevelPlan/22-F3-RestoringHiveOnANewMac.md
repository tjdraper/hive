# F3. Restoring Hive on a new Mac

**Phase F — Recovery** · Mixed, 2 sessions, installed build, needs you

References like §14 point to [00-Info.md](00-Info.md). Read the brainstorm's "Recovery after the Hive Mac is lost" and "Manifests: backup sets that describe themselves".

## Engine

- **Restoring from a recovery file,** only on a Hive with no configuration yet: Beekeeper on the Hive Mac sends the file and the recovery key over its local connection. Hive decrypts the file, encrypts every secret again for its own Secure Enclave, keeps the Hive ID, and forgets the key.
- **Choosing the backup drive again** (§14), since a restored drive has a new volume UUID. Hive checks its `Hive/` marker carries the same Hive ID.
- **Rebuilding the catalog from manifests** (§9): Hive scans the drive's `Hive/` folder and takes over every snapshot whose manifest carries its Hive ID. This also works when Hive's store is lost.
- **Retention and quotas wait** until you confirm in Beekeeper (§10). A drive restored from a Mac backup may have lost its hard links.
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

**Done when:** a restored Hive has the same Hive ID, configuration and snapshots, and backs up the test server without any key being added to it; nothing is removed until retention is started again; the old Beekeeper key is refused and Beekeeper says the identity changed; rotating SSH keys leaves the test server with only the new key; and the tests pass.
