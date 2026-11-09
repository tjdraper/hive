# D4. Confirming destructive actions

**Phase D — Managing backups in Beekeeper (Mac)** · Mixed, 1–2 sessions, installed build

References like §6 point to [00-Info.md](00-Info.md). Read the brainstorm's "Hardening for internet exposure".

## Engine

- **A second Secure Enclave key for each Hive,** protected by `.userPresence`, created and registered by each paired device the first time it needs one. On a Mac without Touch ID, macOS asks for the account password instead. A Hive Mac is often a headless Mac mini reached only through Screen Sharing, so check that the password prompt appears and works there.
- **Changes to servers and jobs:** C1's `ConfirmationRequirement` already says which need confirmation and why. Check them inside the store's write transaction, against the stored values, so a change made in between can't slip through.
- **Each action that needs confirmation carries a fresh signature** from that key over the action, the object it acts on and a nonce from Hive. A session alone is never enough, and Hive refuses the action without one.
- **A changed host key** is confirmed through C2's scan and `PUT /servers/<id>/host-key`, which already replaces the key and names `hostKeyReplaced`. C2's `POST /servers/<id>/ssh-key` names `sshKeyReplaced` when the server had a key. Both are only logged until this slice.
- **The actions in this slice** (§6): deleting snapshots; lowering a quota or a job's tiers; changing a server's host, port, user or credentials; confirming a changed host key; and regenerating the identity. Later slices add their own: E1 the SMTP host, F1 a new recovery key, F3 rotating SSH keys, and G1 opening a pairing window.

- **From C6:** retention applies a stored quota or tiers at its next pass, after a run, once a day or when Hive starts, so refusing an unconfirmed lowering change in the write transaction is what keeps it from removing anything. To say how many snapshots a change would remove, run `TierResolver` on the job's catalog and walk the quota's candidates oldest first with `freesBytes`. Removing one can make its neighbors free more, so the count is an upper bound. Deleting snapshots by hand goes through `SnapshotRemover` on the job queue, so it never meets a run; a removed job's snapshots use the folder names in their catalog entries.

## UI

- **Deleting snapshots:** one, or all of a job's or server's, including for removed jobs and servers whose snapshots stayed (C1)
- **The confirmation** on each change in D1 and D2 that needs it, saying what it will do, such as how many snapshots a lower quota removes
- **A changed host key:** the server shows it, with the old and new fingerprints and the last successful backup, and Confirm New Key
- **Regenerate Identity** in the Hive's settings, which says every device has to pair again. Beekeeper on the Hive Mac pairs again by itself.
- **Another device seeing a changed identity** gets "This Hive's identity has changed, pair again", and never accepts the new key silently (§14). It can only be tried once G1 pairs a second device.

## Tests

- Each confirmed route refuses a request without a signature, with one for a different action or object, and with a reused nonce
- Lowering a quota without confirmation removes nothing

- **From D2:** `QuotaField` and `RetentionFields` already warn when the quota or a tier is lowered, and `DatabasePasswordField` replaces a saved password through Change; their confirmations go on Save in `EditServerSheet` and `JobEditorSheet`.
- **From D1:** `EditServerSheet` already warns when the host, port or user changes; the confirmation goes on its Save. The server page offers "Make Hive's Key" only for a server with no key, which needs no confirmation.

**Done when:** in the installed builds, deleting a snapshot asks for Touch ID and cancelling leaves it; lowering the test server's quota asks first and says what it will remove; a new host key on the test server shows in Beekeeper, and confirming it with Touch ID lets backups run again; regenerating the identity leaves Beekeeper on the Hive Mac paired again; and the tests pass.
