# F2. Recovery file copies in Beekeeper

**Phase F — Recovery** · Mixed, 1 session

References like §14 point to [00-Info.md](00-Info.md).

- **Every paired Beekeeper keeps the latest recovery file,** fetched through the API whenever Hive writes a new one
- **On the Mac, a folder you choose** to keep a copy in too, such as one in iCloud Drive, remembered with a bookmark
- **New Recovery Key** in the Hive's settings (F1), confirmed (§6), showing the new key once. Beekeeper deletes the old copies it manages, and says that copies in Mac backups still open with the old key.
- **The Hive's overview** shows when its recovery file was last written and whether this device has it

**Done when:** in the installed builds, a configuration change puts a new recovery file in Beekeeper's store and the chosen folder; and after a new recovery key, the old copies are gone from both.

- **From F1:** `RecoveryKeyState.fileWrittenAt` is when the data directory's file was last written with the current key, cleared when the key changes. The file's header carries the recovery public key it was written for (`RecoveryFile`), so Beekeeper can tell a copy made with an old key. New Recovery Key can reuse `RecoveryKeySheet`, which already makes and shows a key and saves it confirmed; it needs the wording for replacing a key and the suggestion to rotate SSH keys and change credentials.
