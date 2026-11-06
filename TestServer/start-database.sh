#!/bin/bash
# Starts the MariaDB that runs on the server itself, outside Docker, and gives it the sample data
# the first time.
set -euo pipefail

mkdir -p /run/mysqld
chown mysql:mysql /run/mysqld
mariadbd-safe --user=mysql > /dev/null 2>&1 &

for _ in $(seq 1 60); do
    mariadb-admin ping --silent > /dev/null 2>&1 && break
    sleep 0.5
done

if ! mariadb -e 'USE site' 2> /dev/null; then
    mariadb < /usr/local/share/hive-test/mysql-seed.sql
    echo "Seeded the host's MariaDB"
fi
