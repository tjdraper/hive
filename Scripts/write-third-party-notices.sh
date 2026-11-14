#!/bin/bash
#
# Writes the third-party notices each Mac app shows in its About panel, from the license and notice
# files of the packages it actually links. MIT and Apache 2.0 ask for these to go with every copy of
# the apps. The packages come from what the last Scripts/build-and-test.sh build linked, so a package
# only used by tests or build tools, or resolved but never linked, isn't listed.
#
# Usage:
#   Scripts/write-third-party-notices.sh            rewrite the notices
#   Scripts/write-third-party-notices.sh --check    fail if they're out of date

set -euo pipefail

cd -P "$(dirname "$0")/.."
readonly REPO_ROOT="$PWD"
readonly DERIVED_DATA="build/build-and-test/DerivedData"
readonly INTERMEDIATES="$DERIVED_DATA/Build/Intermediates.noindex"
readonly PRODUCTS="$DERIVED_DATA/Build/Products"
readonly CHECKOUTS="$DERIVED_DATA/SourcePackages/checkouts"
readonly RESOLVED="Hive.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

fail() {
    echo "error: $*" >&2
    exit 1
}

check=0
case "${1:-}" in
    "") ;;
    --check) check=1 ;;
    *) fail "usage: Scripts/write-third-party-notices.sh [--check]" ;;
esac

[[ -d "$CHECKOUTS" ]] || fail "no build to read; run Scripts/build-and-test.sh first"

# Xcode keeps each package module's build folder under its package's name, which is the name in the
# package's manifest. That's usually its checkout folder's name, but not always (GRDB.swift's is GRDB).
checkout_for_package() {
    local name="$1"
    if [[ -d "$CHECKOUTS/$name" ]]; then
        echo "$name"
        return
    fi
    local matches=()
    local manifest
    for manifest in "$CHECKOUTS"/*/Package.swift; do
        if perl -0ne "exit(!/Package\\s*\\(\\s*name:\\s*\"\\Q$name\\E\"/)" "$manifest"; then
            matches+=("$(basename "$(dirname "$manifest")")")
        fi
    done
    [[ ${#matches[@]} -eq 1 ]] || fail "can't tell which checkout the package $name is"
    echo "${matches[0]}"
}

# Prints the checkout folder of every third-party package linked through the link file lists and
# frameworks given, one per line. The project's own packages are skipped.
linked_packages() {
    local link_lists=("$@")
    local list module build_dirs package
    for list in "${link_lists[@]}"; do
        [[ -f "$list" ]] || fail "no link file list at $list; run Scripts/build-and-test.sh first"
        # Package modules link from the products folder. The target's own files link from its intermediates.
        { grep "/Build/Products/" "$list" || true; } | sed -E 's#.*/([^/]+)\.o$#\1#' | while read -r module; do
            build_dirs=$(compgen -G "$INTERMEDIATES/*.build/*/$module-t.build" || true)
            [[ -n "$build_dirs" ]] || fail "can't tell which package the module $module is from"
            echo "$build_dirs" | sed -E "s#^$INTERMEDIATES/([^/]+)\\.build/.*#\\1#" | sort -u | while read -r package; do
                if [[ -f "$REPO_ROOT/$package/Package.swift" ]]; then
                    continue
                fi
                checkout_for_package "$package"
            done
        done
    done
}

embedded_framework_packages() {
    local frameworks_dir="$1"
    local framework
    [[ -d "$frameworks_dir" ]] || return 0
    for framework in "$frameworks_dir"/*.framework; do
        [[ -e "$framework" ]] || continue
        checkout_for_package "$(basename "$framework" .framework)"
    done
}

package_url() {
    local checkout="$1"
    local count index identity
    count=$(plutil -extract pins raw -o - "$RESOLVED")
    for ((index = 0; index < count; index++)); do
        identity=$(plutil -extract "pins.$index.identity" raw -o - "$RESOLVED")
        if [[ "$identity" == "$(echo "$checkout" | tr '[:upper:]' '[:lower:]')" ]]; then
            plutil -extract "pins.$index.location" raw -o - "$RESOLVED" | sed 's/\.git$//'
            return
        fi
    done
    fail "$checkout isn't in $RESOLVED"
}

license_file() {
    local file
    for file in "$CHECKOUTS/$1"/{LICENSE,LICENSE.txt,LICENSE.md,COPYING}; do
        [[ -f "$file" ]] && { echo "$file"; return; }
    done
    fail "$1 has no license file"
}

is_apache() {
    local top
    top=$(head -n 5 "$1")
    [[ "$top" == *"Apache License"* && "$top" == *"Version 2.0"* ]]
}

notice_file() {
    local file
    for file in "$CHECKOUTS/$1"/{NOTICE,NOTICE.txt,NOTICE.md}; do
        [[ -f "$file" ]] && { echo "$file"; return; }
    done
    return 0
}

# Writes the notices for the packages on standard input, after the intro line given.
write_notices() {
    local intro="$1"
    local extra="$2"
    local packages=()
    local package license notice apache_license=""
    while read -r package; do
        packages+=("$package")
    done

    echo "$intro"
    echo
    if [[ -n "$extra" ]]; then
        echo "$extra"
        echo
    fi
    for package in ${packages[@]+"${packages[@]}"}; do
        license=$(license_file "$package")
        echo "$package"
        package_url "$package"
        echo
        if is_apache "$license"; then
            [[ -n "$apache_license" ]] || apache_license="$license"
            echo "Licensed under the Apache License, Version 2.0, at the end of these notices."
            echo
            notice=$(notice_file "$package")
            if [[ -n "$notice" ]]; then
                cat "$notice"
                echo
            fi
        else
            cat "$license"
            echo
        fi
        echo "--"
        echo
    done
    if [[ -n "$apache_license" ]]; then
        # Packages append different appendices and exceptions after the terms. The terms are the same.
        sed '/END OF TERMS AND CONDITIONS/q' "$apache_license"
    fi
}

sorted_unique() {
    sort -fu
}

rsync_version=$(sed -n 's/^readonly VERSION="\(.*\)"$/\1/p' Scripts/build-rsync.sh)
[[ -n "$rsync_version" ]] || fail "can't read rsync's version from Scripts/build-rsync.sh"
rsync_notice="rsync $rsync_version
https://rsync.samba.org

Hive runs rsync as a separate program, unmodified, under the GNU General Public License version 3. Its license is in Hive.app at Contents/Resources/rsync/COPYING, and its source is at https://download.samba.org/pub/rsync/src/rsync-$rsync_version.tar.gz.

--"

ios_packages=$(linked_packages "$INTERMEDIATES/Hive.build/Debug-iphonesimulator/Beekeeper.build/Objects-normal/arm64/Beekeeper.LinkFileList"
    embedded_framework_packages "$PRODUCTS/Debug-iphonesimulator/Beekeeper (Debug).app/Frameworks")
[[ -z "$ios_packages" ]] || fail "Beekeeper for iPhone and iPad links $(echo "$ios_packages" | sorted_unique | tr '\n' ' ')and has nowhere to show their notices"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

{
    linked_packages \
        "$INTERMEDIATES/Hive.build/Debug/Hive.build/Objects-normal/arm64/Hive (Debug).LinkFileList" \
        "$INTERMEDIATES/Hive.build/Debug/HiveDaemon.build/Objects-normal/arm64/HiveDaemon.LinkFileList"
    embedded_framework_packages "$PRODUCTS/Debug/Hive (Debug).app/Contents/Frameworks"
} | sorted_unique | write_notices "Hive includes the following third-party software." "$rsync_notice" > "$work_dir/Hive.txt"

{
    linked_packages "$INTERMEDIATES/Hive.build/Debug/Beekeeper.build/Objects-normal/arm64/Beekeeper (Debug).LinkFileList"
    embedded_framework_packages "$PRODUCTS/Debug/Beekeeper (Debug).app/Contents/Frameworks"
} | sorted_unique | write_notices "Beekeeper includes the following third-party software." "" > "$work_dir/Beekeeper.txt"

readonly HIVE_NOTICES="Hive/About/ThirdPartyNotices.txt"
readonly BEEKEEPER_NOTICES="Beekeeper/About/ThirdPartyNotices.txt"

if [[ $check -eq 1 ]]; then
    stale=()
    cmp -s "$work_dir/Hive.txt" "$HIVE_NOTICES" || stale+=("$HIVE_NOTICES")
    cmp -s "$work_dir/Beekeeper.txt" "$BEEKEEPER_NOTICES" || stale+=("$BEEKEEPER_NOTICES")
    [[ ${#stale[@]} -eq 0 ]] || fail "out of date: ${stale[*]}; run Scripts/write-third-party-notices.sh"
    exit 0
fi

mkdir -p "$(dirname "$HIVE_NOTICES")" "$(dirname "$BEEKEEPER_NOTICES")"
cp "$work_dir/Hive.txt" "$HIVE_NOTICES"
cp "$work_dir/Beekeeper.txt" "$BEEKEEPER_NOTICES"
echo "Wrote $HIVE_NOTICES and $BEEKEEPER_NOTICES"
