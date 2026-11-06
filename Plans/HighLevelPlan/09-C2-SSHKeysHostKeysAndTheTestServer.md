# C2. SSH keys, host keys and the test server

**Phase C — Backups in Hive** · Engine, 1 session

References like §11 point to [00-Info.md](00-Info.md). Look at `../site-backups/src/Ssh` and `../site-backups/src/Backup/RsyncOverlay.php` for how the PHP version connects, `../site-backups/docker/docker-compose.prod.yml` for its setup, and Locus Git Gui's `GitRunner/` for running a command-line tool.

## The test server

A Docker setup in the repository, started by a script (Part 2, "Development servers and drives"):

- a Linux container running `sshd` and the same rsync version as your real servers, with sample files, a script that changes some of them between runs, and the Docker socket mounted so `docker exec` reaches its neighbors the way it does on a real server. C4 adds the database services.
- a script that gives it a new host key, for checking a changed key

## Hive

- **SSH keys** (§11): Hive generates an Ed25519 key for each server, or one for the whole Hive (decide, §19), and stores the private key as a secret. The API returns the public key, and the line to add to `authorized_keys`, with a `from=` restriction to the Hive Mac's addresses offered.
- **Handing the key to `ssh`:** decide between a short-lived file in a `0700` folder deleted after use, and an `ssh-agent` run by Hive (§19). Record the decision in §11.
- **An `SSHRunner`** that builds every `ssh` command the same way: `-F /dev/null`, so the user's own `~/.ssh/config` never applies; `BatchMode=yes`; `StrictHostKeyChecking=yes` with Hive's own `known_hosts` file; `HostKeyAlias` set to the server's ID; `IdentitiesOnly=yes` with Hive's key; a connect timeout; and `ServerAliveInterval` so a stalled connection ends. It captures output, supports cancellation, and tells a changed host key apart from a refused login and an unreachable host.
- **Host keys through the API:** scan a server's key with `ssh-keyscan`, return its SHA-256 fingerprints, and record it only once a device confirms it. D4 adds confirming a changed key.
- **Where the host key goes:** C1 added `server.hostKey`, empty until a device confirms one, and cleared when the server's host, port or user changes. Decide its form here, and write Hive's `known_hosts` from it.
- **Test connection** through the API: connects with Hive's key and runs a harmless command.
- **Logging:** connection results and why one failed. Never hostnames or users.

## Tests

- Every command the runner builds has the options above, and never `StrictHostKeyChecking=no`
- Recorded `ssh` output for a changed key, a refused login and an unreachable host is told apart correctly
- A host key is never written to `known_hosts` before it's confirmed

**Done when:** through the Developer window and the development daemon, the test server's host key is scanned, recorded once confirmed, and a test connection passes with Hive's key; after the test server gets a new host key, the connection is refused and reported as a changed key; and the tests pass.
