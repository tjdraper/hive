# C4. Database dumps

**Phase C — Backups in Hive** · Engine, 1 session

References like §9 point to [00-Info.md](00-Info.md). Look at `../site-backups/src/Backup/Sql`, including the `.phtml` dump scripts.

- **MySQL and MariaDB:** `mariadb-dump` or `mysqldump`, whichever the container or host has, with `--single-transaction`, `--routines` and `--events`, and `--no-tablespaces` so a user without extra privileges can dump on MySQL 8. Compressed with gzip on the Hive Mac.
- **Postgres:** `pg_dump` in its custom format
- **In a Docker container or on the host** (§8). A container is found by its Swarm or Compose service name, and exactly one running container must match (§11). The PHP version's `docker ps -f name=` also matches names that only contain it.
- **Streamed over SSH** straight into the snapshot's `databases/` folder, with no file left on the server or in the container (§9)
- **Passwords never on a command line** (§11): not in the `ssh` command, not in `docker exec` arguments or its `-e`, and not in the dump command. They're passed through standard input. Decide the exact way for each database kind.
- **A failed dump fails its step:** a non-zero exit anywhere in the pipeline, an empty dump, or a MySQL dump without its closing "Dump completed" line
- **The test server** gains MariaDB 11, MySQL 8 and Postgres running as Swarm services with sample data, including a stored routine, and a database on the SSH container itself for the host case.

## Tests

- No command built for any database kind or location contains the password
- Each failure above is caught, using recorded output
- No match, or more than one match, for a service name fails the step

**Done when:** dumps of all three databases on the test server restore into fresh containers with the same row counts and routines; `ps` on the test server during a dump shows no password; a wrong password fails the step with a clear reason; and the tests pass.
