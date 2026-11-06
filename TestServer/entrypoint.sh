#!/bin/bash
# Keeps the host keys, authorized_keys and sample files in volumes, so they survive a rebuild. The
# MariaDB running on the server itself, for backing up a database on the host, keeps its data only
# until the container is rebuilt.
set -euo pipefail

mkdir -p /etc/ssh/keys /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

if [[ ! -f /etc/ssh/keys/ssh_host_ed25519_key ]]; then
    /usr/local/bin/new-host-key.sh --no-restart
fi

if [[ ! -d /srv/sites ]]; then
    /usr/local/bin/seed-files.sh
fi

/usr/local/bin/start-database.sh

exec /usr/sbin/sshd -D -e
