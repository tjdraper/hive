#!/usr/bin/env bash
#
# Runs the test server in Docker: sshd and rsync on 127.0.0.1:2222, logging in as root with keys only,
# with sample files under /srv/sites/example and the Docker socket mounted. Beside it run MariaDB 11,
# MySQL 8.4 and Postgres 18 containers named as Swarm would name them, and MariaDB runs on the server
# itself. Each has sample data for user `site`, in a database named for it so one job can dump them
# all: `site` in the MariaDB container, `shop` in MySQL, `blog` in Postgres and `notes` on the server
# (see TestServer/databases).
# Development backs this up, never a real server.
#
# Usage:
#   Scripts/test-server.sh up                  build and start it, then show its host key fingerprints
#   Scripts/test-server.sh down                stop it, keeping its keys and files
#   Scripts/test-server.sh reset               stop it and delete its keys, authorized_keys, files and databases
#   Scripts/test-server.sh authorize '<line>'  add a line to root's authorized_keys, such as Hive's
#   Scripts/test-server.sh fingerprints        show its host key fingerprints
#   Scripts/test-server.sh new-host-key        give it new host keys, to check that Hive refuses them
#   Scripts/test-server.sh change-files        edit, add and remove some sample files between runs
#   Scripts/test-server.sh rsync-version       show the rsync version it runs
#   Scripts/test-server.sh logs                follow sshd's log
#   Scripts/test-server.sh restore <database> <dump>
#                                              restore a dump Hive made into a new container and compare
#                                              it with its source: mariadb, mysql, postgres or host

set -euo pipefail

invoked_from="$PWD"
script=$(realpath "$0")
cd -P "$(dirname "$0")/../TestServer"

compose() {
    docker compose "$@"
}

in_server() {
    compose exec -T ssh "$@"
}

# The sample database's row count and objects, as its own user sees them in database $3 of container
# $2 with client $1.
source_mysql_summary() {
    local client="$1" container="$2" database="$3"
    # The seed's test password, written for an option file.
    docker exec -i "$container" sh -c 'umask 077; cat > /tmp/hive-summary.cnf' <<'OPTIONS'
[client]
user=site
password="Hive t3st: \"double\" 'single' \\back $HOME #hash"
OPTIONS
    docker exec -i "$container" sh -c "$client --defaults-extra-file=/tmp/hive-summary.cnf --batch --skip-column-names $database; rm /tmp/hive-summary.cnf" \
        < databases/mysql-summary.sql
}

# The same, as root in a scratch container, where the restored objects' owner doesn't exist.
scratch_mysql_summary() {
    docker exec -i "$2" "$1" -uroot --batch --skip-column-names "$3" < databases/mysql-summary.sql
}

postgres_summary() {
    docker exec -i "$1" psql -U postgres -d "$2" -At -F $'\t' < databases/postgres-summary.sql
}

service_container() {
    docker ps -q --filter "label=com.docker.swarm.service.name=hive-test_$1"
}

# Starts a throwaway container of image $1 and prints its ID once command $2 succeeds in it.
start_scratch() {
    local image="$1" ready="$2"
    shift 2
    local container
    container=$(docker run -d --rm "$@" "$image")
    for _ in $(seq 1 120); do
        if docker exec "$container" sh -c "$ready" > /dev/null 2>&1; then
            echo "$container"
            return
        fi
        sleep 1
    done
    docker rm -f "$container" > /dev/null
    echo "error: $image didn't start" >&2
    exit 1
}

restore() {
    local usage="usage: Scripts/test-server.sh restore <mariadb|mysql|postgres|host> <dump>"
    local kind="${1:?$usage}" dump="${2:?$usage}"
    [[ "$dump" == /* ]] || dump="$invoked_from/$dump"
    local source_summary restored_summary scratch
    case "$kind" in
    mariadb | host | mysql)
        local client=mariadb image=mariadb:11 ready="healthcheck.sh --connect" empty_root=MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1
        if [[ "$kind" == mysql ]]; then
            client=mysql image=mysql:8.4 ready="mysqladmin ping --host=127.0.0.1 --silent" empty_root=MYSQL_ALLOW_EMPTY_PASSWORD=yes
        fi
        local database=site
        [[ "$kind" == mysql ]] && database=shop
        [[ "$kind" == host ]] && database=notes
        if [[ "$kind" == host ]]; then
            source_summary=$(source_mysql_summary mariadb "$(compose ps -q ssh)" "$database")
        else
            source_summary=$(source_mysql_summary "$client" "$(service_container "$kind")" "$database")
        fi
        scratch=$(start_scratch "$image" "$ready" -e "$empty_root")
        docker exec "$scratch" "$client" -uroot -e "CREATE DATABASE $database"
        gunzip -c "$dump" | docker exec -i "$scratch" "$client" -uroot "$database"
        restored_summary=$(scratch_mysql_summary "$client" "$scratch" "$database")
        ;;
    postgres)
        source_summary=$(postgres_summary "$(service_container postgres)" blog)
        scratch=$(start_scratch postgres:18 "pg_isready --host=127.0.0.1 --username=postgres" -e POSTGRES_PASSWORD=hive-test-superuser)
        docker exec "$scratch" createdb -U postgres blog
        docker exec -i "$scratch" pg_restore -U postgres --no-owner --exit-on-error -d blog < "$dump"
        restored_summary=$(postgres_summary "$scratch" blog)
        ;;
    *)
        echo "$usage" >&2
        exit 64
        ;;
    esac
    docker rm -f "$scratch" > /dev/null

    echo "Test server:"
    sed 's/^/  /' <<< "$source_summary"
    echo "Restored into a new container:"
    sed 's/^/  /' <<< "$restored_summary"
    if [[ "$source_summary" != "$restored_summary" ]]; then
        echo "error: they differ" >&2
        exit 1
    fi
    echo "They match."
}

fingerprints() {
    in_server bash -c 'for key in /etc/ssh/keys/ssh_host_*_key.pub; do ssh-keygen -l -f "$key"; done'
}

case "${1:-}" in
up)
    compose up -d --build --wait
    echo "Test server on 127.0.0.1:2222, user root. Host keys:"
    fingerprints
    ;;
down)
    compose down
    ;;
reset)
    compose down --volumes
    ;;
authorize)
    line="${2:?usage: Scripts/test-server.sh authorize '<authorized_keys line>'}"
    printf '%s\n' "$line" | in_server bash -c '
        read -r line
        grep -qxF "$line" /root/.ssh/authorized_keys || printf "%s\n" "$line" >> /root/.ssh/authorized_keys
        echo "root has $(grep -c . /root/.ssh/authorized_keys) authorized keys"'
    ;;
fingerprints)
    fingerprints
    ;;
new-host-key)
    in_server /usr/local/bin/new-host-key.sh
    ;;
change-files)
    in_server /usr/local/bin/change-files.sh
    ;;
rsync-version)
    in_server bash -c 'rsync --version | head -n 1'
    ;;
logs)
    compose logs -f ssh
    ;;
restore)
    restore "${2:-}" "${3:-}"
    ;;
*)
    sed -n '3,23p' "$script" | sed 's/^# \{0,1\}//'
    exit 64
    ;;
esac
