#!/bin/bash
# Gives the server new host keys, as a reinstalled or impersonated server would have, and makes sshd use them.
set -euo pipefail

rm -f /etc/ssh/keys/ssh_host_*
for type in ed25519 ecdsa rsa; do
    ssh-keygen -q -t "$type" -N '' -f "/etc/ssh/keys/ssh_host_${type}_key"
done

# sshd is the container's first process. SIGHUP makes it start again in place, loading the new keys.
if [[ "${1:-}" != "--no-restart" ]]; then
    kill -HUP 1
fi

for type in ed25519 ecdsa rsa; do
    ssh-keygen -l -f "/etc/ssh/keys/ssh_host_${type}_key.pub"
done
