#!/bin/bash
#
# Writes the launchd property list that starts Hive's daemon.
#
# The Hive target runs it at build time to put the system daemon's plist in Hive.app, where
# SMAppService finds it. install-test-build.sh --mac runs it for the development daemon, a user agent
# started from the Debug build.
#
# Usage:
#   Scripts/write-launchd-plist.sh --label <label> --mach-service <name> --output <file> \
#       (--bundle-program <path inside the app> --associated-bundle-id <bundle ID> | --program <absolute path>)
#

set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

usage() {
    sed -n '/^# Usage:/,/^#$/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//' >&2
    exit 2
}

label="" mach_service="" output="" bundle_program="" associated_bundle_id="" program=""
while [[ $# -gt 0 ]]; do
    [[ $# -ge 2 ]] || usage
    case "$1" in
        --label) label="$2" ;;
        --mach-service) mach_service="$2" ;;
        --output) output="$2" ;;
        --bundle-program) bundle_program="$2" ;;
        --associated-bundle-id) associated_bundle_id="$2" ;;
        --program) program="$2" ;;
        *) usage ;;
    esac
    shift 2
done

[[ -n "$label" && -n "$mach_service" && -n "$output" ]] || usage

# An empty prefix leaves a label such as ".Hive.Daemon", which launchd accepts but nothing else expects.
for name in "$label" "$mach_service" "$associated_bundle_id"; do
    [[ -z "$name" || "$name" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] \
        || fail "'$name' isn't a reverse-DNS name; check BUNDLE_ID_PREFIX in Configuration/Signing.local.xcconfig"
done

# Values go into the XML as they are.
[[ "$program$bundle_program" != *[\<\>\&]* ]] || fail "the program's path holds <, > or &"

if [[ -n "$bundle_program" && -n "$associated_bundle_id" && -z "$program" ]]; then
    program_entry="    <key>BundleProgram</key>
    <string>$bundle_program</string>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>$associated_bundle_id</string>
    </array>"
elif [[ -n "$program" && -z "$bundle_program$associated_bundle_id" ]]; then
    program_entry="    <key>Program</key>
    <string>$program</string>"
else
    usage
fi

mkdir -p "$(dirname "$output")"

# Umask 077 keeps everything the daemon creates private to its user unless it chooses otherwise.
cat > "$output" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
$program_entry
    <key>MachServices</key>
    <dict>
        <key>$mach_service</key>
        <true/>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>Umask</key>
    <integer>63</integer>
</dict>
</plist>
PLIST

plutil -lint -s "$output"
