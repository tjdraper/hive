#!/bin/bash
#
# Disposable Linux machines for trying Scout on something shaped like a real server. Each is an
# OrbStack machine, which has its own init system, users, processes and Docker, on a kernel shared
# with OrbStack's other machines.
#
#   Debian (the default): systemd, Docker in Swarm mode running a few services, a few hundred
#   processes, and /home on a filesystem of its own.
#   Alpine (--alpine): OpenRC and doas instead of sudo, and a few hundred processes.
#
# Usage:
#   Scripts/scout-test-vm.sh [--alpine] create       Make the machine and start its services
#   Scripts/scout-test-vm.sh [--alpine] install [--ssh-user <name>] < code
#                                                    Install Scout as the pasted command does, from
#                                                    the Linux build of Scripts/build-scout.sh
#   Scripts/scout-test-vm.sh [--alpine] uninstall    Uninstall Scout
#   Scripts/scout-test-vm.sh [--alpine] manage status|uninstall
#   Scripts/scout-test-vm.sh [--alpine] manage update [<folder>]
#                                                    Send hive-scout manage a request as Hive would, as
#                                                    deploy through Scout's sudo or doas rule. An update
#                                                    sends the binary for the machine's CPU and its
#                                                    statement, from the folder or the Linux build
#   Scripts/scout-test-vm.sh [--alpine] measure-installed <seconds>
#                                                    Report the installed service's CPU and memory
#   Scripts/scout-test-vm.sh [--alpine] delete       Remove the machine
#   Scripts/scout-test-vm.sh copy                    Copy the Linux build into the Debian machine
#   Scripts/scout-test-vm.sh measure <seconds> [--tls <host>:<port> --pin <hex>]
#                                                    Run hive-scout watch as Scout's user and report
#                                                    its CPU and memory
#
# From inside a machine, the Mac is host.orb.internal.

set -euo pipefail

cd -P "$(dirname "$0")/.."

machine="hive-scout-vm"
alpine=false
if [[ ${1:-} == --alpine ]]; then
    machine="hive-scout-alpine"
    alpine=true
    shift
fi

in_machine() {
    orb run -m "$machine" -u root bash -euo pipefail -c "$1"
}

create_debian() {
    orb create debian:bookworm "$machine"

    in_machine "
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -qq -y docker.io sudo > /dev/null
        systemctl enable --now docker
        docker swarm init > /dev/null
        useradd --create-home --shell /bin/bash deploy
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

    # /home on an ext4 filesystem of its own, as many servers have, so Scout's service can be seen
    # to report it although the service mounts /home read-only. What /home held is copied onto it.
    in_machine "
        truncate -s 2G /var/home.img
        mkfs.ext4 -q /var/home.img
        mkdir -p /mnt/new-home
        mount -o loop /var/home.img /mnt/new-home
        cp -a /home/. /mnt/new-home/
        umount /mnt/new-home
        rmdir /mnt/new-home
        echo '/var/home.img /home ext4 loop 0 2' >> /etc/fstab
        mount /home
    "

    echo "Waiting for the services to start..."
    sleep 30
    in_machine "echo \"\$(ls /proc | grep -c '^[0-9]') processes, \$(docker ps -q | wc -l) containers\""
}

create_alpine() {
    orb create alpine:3.22 "$machine"
    orb run -m "$machine" -u root sh -c "apk add -q bash"

    # Workers started at boot by OpenRC's local service, as a server's own daemons would be.
    in_machine "
        apk add -q doas coreutils
        # OrbStack's Alpine comes with sudo, which most Alpine servers don't have.
        apk del -q sudo
        adduser -D -s /bin/sh deploy
        cat > /etc/local.d/scout-test-workers.start <<'WORKERS'
#!/bin/sh
for i in \$(seq 250); do su -s /bin/sh nobody -c 'exec sleep 2147483647' & done
WORKERS
        chmod 755 /etc/local.d/scout-test-workers.start
        rc-update add local default > /dev/null
        rc-service local restart > /dev/null
    "
    sleep 5
    in_machine "echo \"\$(ls /proc | grep -c '^[0-9]') processes\""
}

linux_build() {
    local arch
    # Not reading standard input, which holds the code for install.
    arch=$(orb run -m "$machine" uname -m < /dev/null)
    local binary="build/scout/linux/hive-scout-linux-$arch"
    if [[ ! -f $binary ]]; then
        echo "error: $binary is missing; run Scripts/build-scout.sh first" >&2
        exit 1
    fi
    echo "$binary"
}

copy() {
    local binary
    binary=$(linux_build)
    # OrbStack shares the Mac's files with its machines under /mnt/mac.
    in_machine "install -o root -g root -m 0755 '/mnt/mac$PWD/$binary' /usr/local/bin/hive-scout"
}

# What the pasted command does, but copying the binary from the Mac, since a development build has no
# GitHub release to download: into a private folder, checked against its SHA-256, then installed with
# the code read from this script's standard input.
install_scout() {
    local options=""
    if [[ $# -gt 0 ]]; then
        [[ $# -eq 2 && $1 == --ssh-user ]] || { echo "usage: install [--ssh-user <name>] < code" >&2; exit 64; }
        options="--ssh-user $(printf '%q' "$2")"
    fi
    local binary hash
    binary=$(linux_build)
    hash=$(shasum -a 256 "$binary" | cut -d ' ' -f 1)
    in_machine "
        folder=\$(mktemp -d)
        trap 'rm -rf \"\$folder\"' EXIT
        cp '/mnt/mac$PWD/$binary' \"\$folder/hive-scout\"
        echo '$hash  '\"\$folder/hive-scout\" | sha256sum -c > /dev/null
        chmod 700 \"\$folder/hive-scout\"
        \"\$folder/hive-scout\" install $options
    "

    # OrbStack's machines are containers, and OrbStack turns off systemd's lockdown for every service
    # in them with a drop-in. One named to sort after it turns Scout's back on, from Scout's own unit,
    # so the machine runs Scout as a server would. Rewritten only when the unit changed, so enrolling
    # again still reloads Scout rather than restarting it.
    in_machine "
        lxc=/run/systemd/system/service.d/zzz-lxc-service.conf
        unit=/etc/systemd/system/hive-scout.service
        dropIn=\$unit.d/zzzz-scout-test.conf
        if [[ -f \$lxc && -f \$unit ]]; then
            keys=\$(grep -oE '^[A-Za-z]+' \$lxc | paste -sd '|')
            mkdir -p \$unit.d
            { echo '[Service]'; grep -E \"^(\$keys)=\" \$unit; } > \$dropIn.new
            if cmp -s \$dropIn.new \$dropIn; then
                rm \$dropIn.new
            else
                mv \$dropIn.new \$dropIn
                systemctl daemon-reload
                systemctl restart hive-scout
            fi
        fi
    "
}

uninstall_scout() {
    in_machine "
        /usr/local/bin/hive-scout uninstall
        rm -rf /etc/systemd/system/hive-scout.service.d
        if command -v systemctl > /dev/null; then systemctl daemon-reload; fi
    "
}

# What Hive does over SSH: one request line on hive-scout manage's standard input, an update's binary
# after it, run as deploy through Scout's rule, which allows that command and no arguments.
manage() {
    local request="${1:-}" folder="${2:-build/scout/linux}" line arch binary
    local elevate=(sudo -n)
    if $alpine; then elevate=(doas -n); fi
    case "$request" in
        status | uninstall)
            line=$(jq -cn --arg request "$request" '{request: $request}')
            echo "$line" | orb run -m "$machine" -u deploy "${elevate[@]}" /usr/local/bin/hive-scout manage
            ;;
        update)
            arch=$(orb run -m "$machine" uname -m < /dev/null)
            binary="$folder/hive-scout-linux-$arch"
            [[ -f $binary && -f $binary.statement ]] || { echo "error: no $binary and statement" >&2; exit 1; }
            line=$(jq -cn --rawfile statement "$binary.statement" --argjson length "$(wc -c < "$binary")" \
                '{request: "update", statement: $statement, binaryLength: $length}')
            { echo "$line"; cat "$binary"; } | orb run -m "$machine" -u deploy "${elevate[@]}" /usr/local/bin/hive-scout manage
            ;;
        *) echo "usage: manage status|uninstall|update [<folder>]" >&2; exit 64 ;;
    esac
}

# Prints the CPU and memory used by the process the given shell command prints the PID of, over
# the given number of seconds, run inside the machine.
report_usage() {
    local find_pid="$1" seconds="$2"
    in_machine "
        pid=\$($find_pid)
        [[ -n \$pid && \$pid != 0 ]] || { echo 'error: Scout isn'\''t running' >&2; exit 1; }
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
        containers=\$(command -v docker > /dev/null && docker ps -q | wc -l || echo 0)
        echo \"processes: \$(ls /proc | grep -c '^[0-9]'), containers: \$containers\"
        awk -v user=\$((end_user - start_user)) -v kernel=\$((end_system - start_system)) -v hz=\$ticks_per_second \
            -v start=\$start -v end=\$end 'BEGIN {
                seconds = end - start
                printf \"cpu: %.3f%% of one core over %.0f seconds (user %.3f%%, system %.3f%%)\n\",
                    (user + kernel) / hz / seconds * 100, seconds, user / hz / seconds * 100, kernel / hz / seconds * 100
            }'
        grep -E '^(VmRSS|VmHWM|RssAnon|RssFile|Threads)' /proc/\$pid/status
    "
}

measure() {
    local seconds="${1:?usage: measure <seconds> [--tls <host>:<port> --pin <hex>]}"
    shift
    local arguments="watch $*"

    # A transient service as Scout's own user, with the same caps the installed service has, so the
    # figures are what a server would see. The samples it prints are thrown away, since the
    # installed service doesn't write them to the journal.
    in_machine "
        id hive-scout > /dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin hive-scout
        systemctl stop hive-scout-measure 2> /dev/null || true
        systemd-run --unit=hive-scout-measure --uid=hive-scout --property=CPUQuota=5% \
            --property=MemoryMax=64M --property=Nice=10 --property=IOSchedulingClass=idle \
            --property=StandardOutput=null \
            /usr/local/bin/hive-scout $arguments > /dev/null
    "

    # Readings start after the first sample and the connection, so neither start-up nor the 10-second
    # mark Scout waits for counts toward the average.
    sleep 15
    report_usage "systemctl show -p MainPID --value hive-scout-measure" "$seconds"
    in_machine "
        echo 'journal, this run:'
        invocation=\$(systemctl show -p InvocationID --value hive-scout-measure)
        journalctl --no-pager -o cat _SYSTEMD_INVOCATION_ID=\$invocation | tail -n 5 | sed 's/^/    /'
        systemctl stop hive-scout-measure
    "
}

measure_installed() {
    local seconds="${1:?usage: measure-installed <seconds>}"
    report_usage "pgrep -u hive-scout hive-scout" "$seconds"
}

case "${1:-}" in
    create) if $alpine; then create_alpine; else create_debian; fi ;;
    install) shift; install_scout "$@" ;;
    uninstall) uninstall_scout ;;
    manage) shift; manage "$@" ;;
    measure-installed) shift; measure_installed "$@" ;;
    copy) copy ;;
    measure) shift; measure "$@" ;;
    delete) orb delete -f "$machine" ;;
    *) sed -n '3,31p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64 ;;
esac
