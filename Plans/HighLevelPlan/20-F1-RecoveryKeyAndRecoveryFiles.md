# F1. Recovery key and recovery files

**Phase F — Recovery** · Mixed, 1–2 sessions

References like §14 point to [00-Info.md](00-Info.md). Read the brainstorm's "Recovery files and disaster recovery".

## Engine

- **The recovery key** (§14): an HPKE key pair. Hive keeps only the public half. The private half is shown once, as a code in readable groups with a check digit so a mistyped one is caught.
- **Recovery files** in a versioned format, encrypted to the recovery key: the Hive ID, the whole configuration, every secret, Hive's SSH keys and its `known_hosts`. Devices aren't included, since every device pairs again after a restore.
- **Written** shortly after any configuration change and once a day, in Hive's data directory
- **A new recovery key** (needs confirmation, §6): new recovery files use it. Older files still open with the old key (§14), so Hive removes the old files in its data directory and suggests rotating SSH keys and changing credentials when the old key may have leaked.

## UI

Built with you:

- **Setup on a new Hive** shows the recovery key once, and doesn't finish until part of it is entered back
- **A Hive set up before this slice** shows a warning in Beekeeper until its recovery key has been saved

## Tests

- A recovery file decrypts with its key and holds everything listed above, including every kind of secret
- The wrong key and a changed byte both fail
- A file written after a new key doesn't open with the old one
- A mistyped recovery key code is caught by its check digit

**Done when:** in the installed builds, the existing Hive gets its recovery key through Beekeeper; a recovery file appears in the data directory and is replaced after a configuration change; and the tests pass.
