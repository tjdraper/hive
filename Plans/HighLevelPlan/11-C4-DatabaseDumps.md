# C4. Database dumps

**Phase C — Backups in Hive** · Engine, 1 session

References like §9 point to [00-Info.md](00-Info.md). Look at `../site-backups/src/Backup/Sql`, including the `.phtml` dump scripts.

- **MySQL and MariaDB:** `mariadb-dump` or `mysqldump`, whichever the container or host has, with `--single-transaction`, `--routines` and `--events`, and `--no-tablespaces` so a user without extra privileges can dump on MySQL 8. Compressed with gzip on the Hive Mac.
- **Postgres:** `pg_dump` in its custom format
- **In a Docker container or on the host** (§8). A container is found by its Swarm or Compose service name, and exactly one running container must match (§11). The PHP version's `docker ps -f name=` also matches names that only contain it.
- **Streamed over SSH** straight into the snapshot's `databases/` folder, with no file left on the server or in the container (§9). C2's `SSHSession.ssh(_:)` hands its command to the server's shell, so anything in it from the configuration has to be quoted.
- **Passwords never on a command line** (§11): not in the `ssh` command, not in `docker exec` arguments or its `-e`, and not in the dump command. They're passed through standard input. Decide the exact way for each database kind.
- **Dump file names** come from the database's name, which C1 keeps unique in its job and to letters, digits, `_`, `$` and `-`.
- **A failed dump fails its step:** a non-zero exit anywhere in the pipeline, an empty dump, or a MySQL dump without its closing "Dump completed" line
- **The test server** gains MariaDB 11, MySQL 8 and Postgres running as Swarm services with sample data, including a stored routine, and a database on the SSH container itself for the host case.

- **From C3:** `BackupRunWorkflow` (`BackupRuns/`) pulls only directories. Dumps go into the same partial snapshot after them, under `databases/`, with the manifest listing each. A job with no directories gets a partial made without the source check.

## Tests

- No command built for any database kind or location contains the password
- Each failure above is caught, using recorded output
- No match, or more than one match, for a service name fails the step

**Decisions (2026-11-06):**

- **Passwords:** MySQL and MariaDB read an option file from standard input, `--defaults-extra-file=/dev/stdin` as their first option, holding the user and the password in double quotes with `\` and `"` escaped. The password is in no process's arguments or environment. pg_dump can't read a password from standard input and refuses a password file that isn't a regular file, so `sh` reads the line into `PGPASSWORD` and runs pg_dump with `exec`. No command line shows it, though root and pg_dump's own user on the server can read its environment. `ssh` takes the input on its standard input, and `docker exec --interactive` passes it on.
- **The commands:** `sh -c '<script>' sh <arguments>`, inside `docker exec --interactive <id>` for a container, with every word single-quoted for the server's shell and no single quote in Hive's scripts, so any login shell reads them the same. MySQL's script runs `mariadb-dump` where it's found, then `mysqldump`, and exits 127 with neither. Postgres connects to `127.0.0.1` over TCP, as the PHP version did. The official Postgres image trusts every connection from `127.0.0.1` unless it was set up otherwise, so on such a server a wrong password still dumps; the test server's Postgres requires one (`--auth-host=scram-sha-256`).
- **Finding a container:** `docker ps --no-trunc` lists each running container's full ID with its Swarm and Compose service labels, and the name has to equal one of them exactly. Listing and dumping are two connections.
- **Streaming:** `ChildProcess` can hand standard output to a handler as it arrives, one piece at a time, so a slow disk holds up `ssh` through the pipe instead of filling memory. MySQL dumps are gzipped by zlib in Hive as they arrive; Postgres's custom format is stored as it comes. The files are `<name>.sql.gz` and `<name>.dump`, made `0600` and never through a link or over an existing file.
- **Failures,** each its own `BackupFailure`: no password stored, Docker unavailable, no container or more than one, no dump tool, the database server unreachable, the login refused, no such database, a missing privilege (such as for a routine another user owns), an empty dump, an incomplete one (no `-- Dump completed` for MySQL, no `PGDMP` header for Postgres), and anything else. ssh's own failures read as the connection's. Standard error is only matched, never logged.
- **In a run:** dumps follow the directories in the same partial. A failed dump stops the run, its file removed. Each run removes the `databases/` folder a failed run left, since every dump is taken whole. The manifest lists each database with its kind and file, and `BackupRun` gains `databases`, each with its time, the bytes dumped and stored, and why it failed.
- **The test server:** Swarm mode stays off on this Mac, so the MariaDB 11, MySQL 8.4 and Postgres 18 containers are Compose services carrying the container names and service labels a Swarm stack named `hive-test` would give them. MariaDB 10.11 runs on the SSH container for the host case. Each has user `site` and, since D2, a database of its own name (`site`, `shop`, `blog`, and `notes` on the host) so one job can dump them all, with 2,500 rows, a view, a trigger, a procedure, a function and an event (Postgres: a view and a function), and a test password holding a space, both quotes, a backslash, `$` and `#`. The routines are owned by `site`: MySQL 8 and MariaDB 10.11 refuse to dump another user's routines without extra privileges. `Scripts/test-server.sh restore <database> <dump>` restores a dump into a new container and compares it with its source.

**Result (2026-11-06):** the tests pass, running Hive's commands with `/bin/sh` against scripts standing in for `docker` and the dump tools, which record their arguments, the option file and `PGPASSWORD`. Through the Developer window and the development daemon, a job for each database on the test server dumped: MariaDB 11 after the existing job's directories, MySQL 8.4 and Postgres 18 in containers, and MariaDB on the host. Each restored into a new container with 2,500 rows and the same view, routines, trigger and event. Process lists sampled continuously during the runs, on this Mac, in the SSH container and in each database container, caught every dump process and never the password. A wrong password failed the Postgres and host MariaDB steps with `databaseLoginRefused`, leaving their partials with an empty `databases/`. The system log gave each dump's kind, where it ran, its time and sizes, and no names. The test drive belonged to the installed Hive since C3, so the development daemon used a separate scratch disk image.

**Done when:** dumps of all three databases on the test server restore into fresh containers with the same row counts and routines; `ps` on the test server during a dump shows no password; a wrong password fails the step with a clear reason; and the tests pass.
