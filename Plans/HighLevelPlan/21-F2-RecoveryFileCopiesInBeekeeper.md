# F2. Recovery file copies in Beekeeper

**Phase F — Recovery** · Mixed, 1 session

References like §14 point to [00-Info.md](00-Info.md).

- **Every paired Beekeeper keeps the latest recovery file,** fetched through the API whenever Hive writes a new one
- **On the Mac, a folder you choose** to keep a copy in too, such as one in iCloud Drive, remembered with a bookmark
- **New Recovery Key** in the Hive's settings (F1), confirmed (§6), showing the new key once. Beekeeper deletes the old copies it manages, and says that copies in Mac backups still open with the old key.
- **The Hive's overview** shows when its recovery file was last written and whether this device has it

## How it was built

- **Hive** gives the latest file at `GET /recovery-file`. `RecoveryKeyState` also carries the key's public half and the file's SHA-256 (`RecoveryFileHeader.digest(of:)`), and live updates send it as `.recovery` right after the job statuses, then whenever `RecoveryFileWriter` writes a file or a new key is saved, through its `changes` broadcaster.
- **Beekeeper's copy** is `Recovery Files/<Hive ID>.hiverecovery` in its Application Support folder, kept by `RecoveryFileCopies`, one per Hive. It fetches the file when its own digest differs from the Hive's, and deletes a copy whose header names a key other than the Hive's. `LiveUpdateFollower` took the live updates loop out of `JobStatusStore` and hands each update to whichever of the two it's for.
- **The chosen folder** is per Hive and per Mac, in Hive settings › Recovery, kept as a security-scoped bookmark in `<Hive ID>.folder.json` beside the copy. The copy there is `<Hive name> <first 8 of the Hive ID>.hiverecovery`, so two Hives with one name never share a file, and it's renamed with the Hive. Choosing another folder or Stop deletes the copy in the old one.
- **Removing a Hive from the list** leaves its copies, since they may be all that's left to bring it back.

**Done when:** in the installed builds, a configuration change puts a new recovery file in Beekeeper's store and the chosen folder; and after a new recovery key, the old copies are gone from both.

- **From F1:** `RecoveryKeyState.fileWrittenAt` is when the data directory's file was last written with the current key, cleared when the key changes. The file's header carries the recovery public key it was written for (`RecoveryFile`), so Beekeeper can tell a copy made with an old key. New Recovery Key can reuse `RecoveryKeySheet`, which already makes and shows a key and saves it confirmed; it needs the wording for replacing a key and the suggestion to rotate SSH keys and change credentials.
