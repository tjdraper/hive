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

- **From D3:** a job's snapshots are listed in `JobSnapshotsSection`, from `GET /jobs/<id>/snapshots`, which is where deleting one goes. Snapshots of removed jobs have no page yet: the route answers 404 once the job is gone. A removal shows in the Job Log as a `RemovalLogEntry` and reaches live updates as `RunEvent.removed`.
- **From D2:** `QuotaField` and `RetentionFields` already warn when the quota or a tier is lowered, and `DatabasePasswordField` replaces a saved password through Change; their confirmations go on Save in `EditServerSheet` and `JobEditorSheet`.
- **From D1:** `EditServerSheet` already warns when the host, port or user changes; the confirmation goes on its Save. The server page offers "Make Hive's Key" only for a server with no key, which needs no confirmation.

**Decisions (2026-11-09):**

- **A confirmation signs the whole request.** Beekeeper asks `POST /confirmation/challenge` for a nonce, then signs `ConfirmationStatement`: the Hive ID, the device ID, the nonce, the method, the path and the body's SHA-256. It goes in a `Hive-Confirmation` header, so request bodies are unchanged. A signature is good for one action on one object with one change, once. Hive answers 428 with the `ConfirmationReason`s when a change needs confirming and the request carried none, and 403 with a `ConfirmationRefusalReason` when the one it carried is no good. Nonces last 5 minutes, long enough to type a password over Screen Sharing.
- **Each route decides inside its write transaction.** `ConfirmedRequest.read` checks the signature and uses up the nonce; the store then compares against the stored values and throws `ConfirmationError.required`, which rolls the change back.
- **The confirmation key** is a Secure Enclave key with `.userPresence`, kept in the device's keychain credential and made the first time a change needs one. Registering it (`PUT /confirmation/key`) is signed by the device's sign-in key, so a session token alone can't register one, and a device keeps its first key: losing it means revoking the device and pairing again. Beekeeper asks with `LAContext.evaluateAccessControl`, off the main actor, and signs with that context, so there's one prompt, which says what the change does.
- **Lowering a quota or tiers** shows, as you edit, how many snapshots it removes (`POST /servers/<id>/quota-estimate`, `POST /jobs/<id>/retention-estimate`), and Save asks for Touch ID saying the same. Changing where Hive connects and replacing a database password ask on Save too. Replacing Hive's SSH key is confirmed in the engine; Beekeeper still only offers a first key.
- **Deleting snapshots** (`DELETE /snapshots/<id>`, `/jobs/<id>/snapshots`, `/servers/<id>/snapshots`) records the request in the store and answers 202. The queue deletes them through `SnapshotRemover` ahead of waiting runs, so a run never picks up a partial that's about to go, and a restart doesn't lose the request. A partial a run is writing to is refused with 409. Snapshots waiting to go show as Being removed. Removed jobs' snapshots are listed on the Overview (`GET /removed-jobs`), and `GET /jobs/<id>/snapshots` now answers for a removed job while it has any. The job log names a removed job from its last entry, or failing that its folders.
- **A changed host key** shows on the server page when a job's last run failed with `hostKeyChanged`: the warning, the last successful backup, a scan started on its own, the old and new fingerprints, and Confirm New Key.
- **Regenerate Identity** makes the new key first, then unpairs every device and ends every session in one go, replaces `identity.key`, and restarts Hive through a graceful shutdown that launchd's `KeepAlive` starts again; the certificate is reissued on the way up. XPC pairing is refused while the restart is pending, so Beekeeper on the Hive Mac can't pin the old key; it retries for up to a minute and pairs with the new one.
- **rsync can report ssh's failure as its own protocol error** (code 12) rather than ssh's 255, depending on which it notices first, about one time in five here. `RsyncResultReader` read ssh's messages only with 255, so a changed host key could show as "failed". It now reads them with either.
- **Buttons:** Delete All Snapshots is a button in its own row, never text in a section header.
- **Space set aside isn't counted.** APFS gives a file rsync writes over the network space past its end (8.5 MB for a 300 MB file here) and takes it back only later, after its cache lets go of the file. Counted right after the run, that space stayed in the job's total for good, so a quota would have removed snapshots early: after the test runs, the total was 78 MB more than the drive held. A file now counts the smaller of its blocks and its size in whole blocks, so a sparse file still counts what it has. A migration has every job counted whole again at the next pass.

**Result (2026-11-10):** the tests pass. In the installed builds, deleting a snapshot asked for Touch ID and cancelling left it; lowering the test server's quota to 0.7 GB said it would remove up to 2 snapshots, asked first, and the next pass removed exactly those 2; a new host key on the test server failed the run as a changed key, showed in Beekeeper with both fingerprints, and confirming it with Touch ID let the next run succeed; regenerating the identity unpaired every device, restarted Hive, and Beekeeper on the Hive Mac paired again by itself.

**Done when:** in the installed builds, deleting a snapshot asks for Touch ID and cancelling leaves it; lowering the test server's quota asks first and says what it will remove; a new host key on the test server shows in Beekeeper, and confirming it with Touch ID lets backups run again; regenerating the identity leaves Beekeeper on the Hive Mac paired again; and the tests pass.
