#!/bin/bash
#
# A disposable Linux machine for trying Scout on something shaped like a real server: systemd, Docker
# in Swarm mode running a few services, and a few hundred processes. It's an OrbStack machine, which
# has its own systemd, users, processes and Docker, on a kernel shared with OrbStack's other machines.
#
# Usage:
#   Scripts/scout-test-vm.sh create            Make the machine and start its services
#   Scripts/scout-test-vm.sh copy              Copy the Linux build from Scripts/build-scout.sh into it
#   Scripts/scout-test-vm.sh measure <seconds> [--tls <host>:<port> --pin <hex>]
#                                              Run Scout as its own user and report its CPU and memory
#   Scripts/scout-test-vm.sh delete            Remove the machine
#
# From inside the machine, the Mac is host.orb.internal.

set -euo pipefail

cd -P "$(dirname "$0")/.."

machine="hive-scout-vm"

in_machine() {
    orb run -m "$machine" -u root bash -euo pipefail -c "$1"
}

create() {
    orb create debian:bookworm "$machine"

    in_machine "
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -qq -y docker.io > /dev/null
        systemctl enable --now docker
        docker swarm init > /dev/null
        useradd --system --no-create-home --shell /usr/sbin/nologin hive-scout
    "

    # A web server, a cache, a database and some workers, as a small server might run, adding up to
    # a few hundred processes with what the machine runs itself.
    # Debian 12's Docker still needs the Compose file version for a stack.
    in_machine "cat > /root/stack.yml" <<'STACK'
version: "3.8"
services:
  web:
    image: nginx:1.27-alpine
    deploy:
      replicas: 3
  cache:
    image: redis:7-alpine
  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_PASSWORD: scout-test-only
  workers:
    image: alpine:3.22
    command: ["sh", "-c", "for i in $$(seq 50); do sleep infinity & done; wait"]
    deploy:
      replicas: 4
STACK
    in_machine "docker stack deploy -c /root/stack.yml scout-test > /dev/null"

    # Workers outside Docker, under a service account of their own, as php-fpm would run.
    in_machine "
        useradd --system --no-create-home --shell /usr/sbin/nologin www-workers
        systemd-run --unit=scout-test-workers --uid=www-workers \
            bash -c 'for i in \$(seq 60); do sleep infinity & done; wait'
    "

    echo "Waiting for the services to start..."
    sleep 30
    in_machine "echo \"\$(ls /proc | grep -c '^[0-9]') processes, \$(docker ps -q | wc -l) containers\""
}

copy() {
    local arch
    arch=$(orb run -m "$machine" uname -m)
    local binary="build/scout/$arch/hive-scout"
    if [[ ! -f $binary ]]; then
        echo "error: $binary is missing; run Scripts/build-scout.sh first" >&2
        exit 1
    fi
    # OrbStack shares the Mac's files with its machines under /mnt/mac.
    in_machine "install -o root -g root -m 0755 '/mnt/mac$PWD/$binary' /usr/local/bin/hive-scout"
}

measure() {
    local seconds="${1:?usage: measure <seconds> [--tls <host>:<port> --pin <hex>]}"
    shift
    local arguments="watch $*"

    # A transient service as Scout's own user, with the same caps the installed service will have,
    # so the figures are what a server would see. The samples it prints are thrown away, since the
    # installed service won't write them to the journal.
    in_machine "
        systemctl stop hive-scout-measure 2> /dev/null || true
        systemd-run --unit=hive-scout-measure --uid=hive-scout --property=CPUQuota=5% \
            --property=MemoryMax=64M --property=Nice=10 --property=IOSchedulingClass=idle \
            --property=StandardOutput=null \
            /usr/local/bin/hive-scout $arguments > /dev/null
    "

    # Readings start after the first sample and the connection, so neither start-up nor the 10-second
    # mark Scout waits for counts toward the average.
    sleep 15
    in_machine "
        pid=\$(systemctl show -p MainPID --value hive-scout-measure)
        [[ \$pid != 0 ]] || { journalctl -u hive-scout-measure --no-pager | tail -n 20; exit 1; }
        ticks_per_second=\$(getconf CLK_TCK)
        user_ticks() { awk '{ print \$14 }' /proc/\$pid/stat; }
        system_ticks() { awk '{ print \$15 }' /proc/\$pid/stat; }
        start_user=\$(user_ticks)
        start_system=\$(system_ticks)
        start=\$(date +%s.%N)
        sleep $seconds
        end_user=\$(user_ticks)
        end_system=\$(system_ticks)
        end=\$(date +%s.%N)
        echo \"processes: \$(ls /proc | grep -c '^[0-9]'), containers: \$(docker ps -q | wc -l)\"
        awk -v user=\$((end_user - start_user)) -v kernel=\$((end_system - start_system)) -v hz=\$ticks_per_second \
            -v start=\$start -v end=\$end 'BEGIN {
                seconds = end - start
                printf \"cpu: %.3f%% of one core over %.0f seconds (user %.3f%%, system %.3f%%)\n\",
                    (user + kernel) / hz / seconds * 100, seconds, user / hz / seconds * 100, kernel / hz / seconds * 100
            }'
        grep -E '^(VmRSS|VmHWM|RssAnon|RssFile|Threads)' /proc/\$pid/status
        echo 'journal, this run:'
        invocation=\$(systemctl show -p InvocationID --value hive-scout-measure)
        journalctl --no-pager -o cat _SYSTEMD_INVOCATION_ID=\$invocation | tail -n 5 | sed 's/^/    /'
        systemctl stop hive-scout-measure
    "
}

case "${1:-}" in
    create) create ;;
    copy) copy ;;
    measure) shift; measure "$@" ;;
    delete) orb delete -f "$machine" ;;
    *) sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64 ;;
esac
