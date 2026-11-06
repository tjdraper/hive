#!/bin/bash
#
# A backup drive for developing Hive: a case-sensitive APFS disk image, kept in build/test-drive and
# mounted as "Hive Test Drive". Development backs up to this, never the real backup drive. Ejecting it
# is how a missing drive is checked.
#
# Usage:
#   Scripts/test-drive.sh mount      create it the first time, then mount it and show its volume UUID
#   Scripts/test-drive.sh eject      eject it, keeping what's on it
#   Scripts/test-drive.sh status     show whether it's mounted, and its volume UUID
#   Scripts/test-drive.sh delete     eject it and delete the image and every snapshot on it

set -euo pipefail

cd -P "$(dirname "$0")/.."

readonly IMAGE="$PWD/build/test-drive/HiveTestDrive.sparsebundle"
readonly VOLUME_NAME="Hive Test Drive"
readonly SIZE="4g"

fail() {
    echo "error: $*" >&2
    exit 1
}

# Prints the mount point of the image's volume, or nothing when it isn't mounted.
mount_point() {
    hdiutil info -plist | /usr/bin/python3 -c '
import plistlib, sys
image = sys.argv[1]
for entry in plistlib.loads(sys.stdin.buffer.read()).get("images", []):
    if entry.get("image-path") == image:
        for entity in entry.get("system-entities", []):
            if "mount-point" in entity:
                print(entity["mount-point"])
' "$IMAGE"
}

show_status() {
    local mounted
    mounted="$(mount_point)"
    if [[ -z "$mounted" ]]; then
        echo "Not mounted."
        return
    fi
    echo "Mounted at $mounted"
    diskutil info "$mounted" | grep -E 'Volume UUID|File System Personality'
}

case "${1:-}" in
mount)
    if [[ ! -d "$IMAGE" ]]; then
        mkdir -p "$(dirname "$IMAGE")"
        # diskutil's replacement can't make a case-sensitive volume, so this stays with hdiutil.
        hdiutil create -quiet -size "$SIZE" -type SPARSEBUNDLE -fs "Case-sensitive APFS" -volname "$VOLUME_NAME" "$IMAGE" \
            2> >(grep -v "is deprecated" >&2)
        echo "Created $IMAGE"
    fi
    [[ -n "$(mount_point)" ]] || diskutil image attach "$IMAGE" >/dev/null
    show_status
    ;;
eject)
    mounted="$(mount_point)"
    [[ -n "$mounted" ]] || { echo "Not mounted."; exit 0; }
    diskutil eject "$mounted" >/dev/null
    echo "Ejected."
    ;;
status)
    [[ -d "$IMAGE" ]] || fail "no test drive yet; run Scripts/test-drive.sh mount"
    show_status
    ;;
delete)
    mounted="$(mount_point)"
    [[ -z "$mounted" ]] || diskutil eject "$mounted" >/dev/null
    rm -rf "$IMAGE"
    echo "Deleted the test drive."
    ;;
*)
    sed -n '/^# Usage:/,/^$/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2
    exit 64
    ;;
esac
