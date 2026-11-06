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

**Decisions (2026-11-06):**

- **One key per server,** made when the server is added. A server removed from Hive is left accepting a key nobody has, and one key can be replaced without touching the others. A server stored before C2 has none until `POST /servers/<id>/ssh-key` makes one. Only the key's 32-byte seed is sealed; the OpenSSH private key file is built from it in memory each time.
- **Handing the key to `ssh`:** an `ssh-agent` of Hive's own for each connection, rather than a file. A file, even deleted at once, sits on disk in the clear and any program running as you could read it meanwhile. The agent's socket is in a `mkdtemp` folder in the user's temporary folder, since a socket path can't pass 104 bytes. `ssh-add -t 120 -` adds the key from standard input, so it leaves the agent on its own if Hive dies. `ssh` gets `IdentityFile` pointing at the public key and `IdentityAgent` at the socket.
- **`server.hostKey`** holds the confirmed key as `<type> <base64>`. Each connection writes a `known_hosts` with only that line, under `HostKeyAlias` set to the server's ID, in the same run folder, which is removed afterward. There's no shared `known_hosts` to keep in step with the store.
- **Scanning and confirming:** `POST /servers/<id>/host-key/scan` runs `ssh-keyscan` and answers with one key's fingerprint, preferring Ed25519, then ECDSA, then RSA. Hive keeps the scanned key in memory for 15 minutes. `PUT /servers/<id>/host-key` with that fingerprint records it, and is refused with 409 when there's no scan, the scan is older, the server's connection changed since, or the fingerprint differs. A device never sends a key itself, only says which scanned one it checked.
- **The routes:** `GET`/`POST /servers/<id>/ssh-key` reads the public key with its `authorized_keys` lines, or makes a new key. `POST /servers/<id>/connection-test` runs `true` and answers with the time taken and, when it failed, why: no key, no confirmed host key, a changed host key, a refused login, unreachable, stalled, or another failure.
- **Audit and confirmation:** confirming a host key and making a key are audited with their fingerprints. Replacing a confirmed host key or an existing SSH key is added to `ConfirmationRequirement` for D4; a server's first of either needs nothing.
- **The test server** is Ubuntu 24.04 with rsync 3.2.7, as on the real servers, on `127.0.0.1:2222` as root with keys only. Its host keys, `authorized_keys` and sample files are in volumes. `Scripts/test-server.sh` starts it and has `authorize`, `new-host-key` and `change-files`.

**Result (2026-11-06):** the tests pass, including ones running the Mac's own `ssh-agent`, `ssh-add` and `ssh-keygen` locally. Through the Developer window and the development daemon: the test server was added and got its own key; a connection test before confirming said `noConfirmedHostKey` without running `ssh`; the scan's fingerprint matched the server's own Ed25519 key; a wrong fingerprint was refused with 409 and the right one recorded; the test failed with `loginRefused` until Hive's line was added to `authorized_keys`, then passed in 0.22 seconds; after `new-host-key` it failed with `hostKeyChanged` and the confirmed key stayed as it was. No run folder or agent was left afterward, and the system log named no host or user. The failure reader's tests use the output recorded against the test server.

**Done when:** through the Developer window and the development daemon, the test server's host key is scanned, recorded once confirmed, and a test connection passes with Hive's key; after the test server gets a new host key, the connection is refused and reported as a changed key; and the tests pass.
