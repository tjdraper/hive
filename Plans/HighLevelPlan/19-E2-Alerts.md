# E2. Alerts

**Phase E — Email** · Engine, 1 session

References like §13 point to [00-Info.md](00-Info.md). Read the brainstorm's "SSH host keys" under "Fixes during the port".

- **What's emailed** (§13):
  - a backup failed, with the reason from the job log, including lost Full Disk Access
  - the backup drive is missing, as one email for the Hive, not one for each job
  - a job is overdue (C5)
  - a snapshot much smaller than the one before
  - a host key changed: the server, old and new fingerprints, and the last successful backup, right away and then daily until it's confirmed or the original key comes back. C2 reports the change but not the new fingerprint: `ssh`'s warning names it on the line after "The fingerprint for the … key sent by the remote host is", or a scan finds it.
  - a server over its quota with only monthly and newest snapshots left (C6)
  - the drive filling up, or the quotas adding up to more than it holds
- **A job that keeps failing** emails on the first failure, then once a day, and once when it succeeds again
- **Alert state in Hive's store,** so a restart never sends one twice or forgets one
- **Emails name servers and jobs,** since you need them to act. Never a secret.

## Tests

- Each alert goes out once, then daily as described, and stops when resolved, across restarts
- A missing drive sends one email however many jobs fail
- Recovery sends exactly one "succeeded again" email

**Done when:** with the test server, stopping its `sshd` sends a failure email and starting it again sends a recovery email; giving it a new host key sends the host key email; ejecting the test drive sends one email; and the tests pass.
