#!/usr/bin/env bash
#
# Runs the test server in Docker: sshd and rsync on 127.0.0.1:2222, logging in as root with keys only,
# with sample files under /srv/sites/example and the Docker socket mounted. Development backs this up,
# never a real server.
#
# Usage:
#   Scripts/test-server.sh up                  build and start it, then show its host key fingerprints
#   Scripts/test-server.sh down                stop it, keeping its keys and files
#   Scripts/test-server.sh reset               stop it and delete its keys, authorized_keys and files
#   Scripts/test-server.sh authorize '<line>'  add a line to root's authorized_keys, such as Hive's
#   Scripts/test-server.sh fingerprints        show its host key fingerprints
#   Scripts/test-server.sh new-host-key        give it new host keys, to check that Hive refuses them
#   Scripts/test-server.sh change-files        edit, add and remove some sample files between runs
#   Scripts/test-server.sh rsync-version       show the rsync version it runs
#   Scripts/test-server.sh logs                follow sshd's log

set -euo pipefail

cd -P "$(dirname "$0")/../TestServer"

compose() {
    docker compose "$@"
}

in_server() {
    compose exec -T ssh "$@"
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
*)
    sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'
    exit 64
    ;;
esac
