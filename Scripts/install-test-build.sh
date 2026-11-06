#!/usr/bin/env bash
#
# Builds the working tree and installs it where it can be tried out.
#
# With --mac, builds Debug copies of Hive and Beekeeper for the Mac, as Xcode's Run does, keeping
# the build between runs so only what changed is built again, then quits the copies it built last
# time and opens the new ones. It also restarts the development daemon: the Debug HiveDaemon, run by
# launchd as a user agent with its own label, Mach service and data folder, apart from an installed
# Hive. It lasts until you log out. A Mach service only exists for a process launchd starts, so the
# daemon is never run straight from Xcode.
#
# With --mac-installed, builds Developer ID copies of both, swaps them in for the copies in
# /Applications, with Hive owned by root, restarts the installed daemon if there is one, and opens
# them. It asks for an administrator password, so run it where you can type one. Permissions,
# entitlements, code signing and the daemon's registration only behave correctly in an installed,
# signed build: macOS attributes a permission to whatever launched the app, so a build run from
# Terminal or Xcode borrows their access. Not notarized. A build made on this Mac carries no
# quarantine flag, so Gatekeeper never checks it.
#
# With --simulator, builds Debug Beekeeper for an iOS simulator, as Xcode's Run does, installs it
# there, launches it and shows the simulator. Permissions on iPad and iPhone are checked through
# TestFlight, never a simulator.
#
# Usage:
#   Scripts/install-test-build.sh --mac                 the Mac, as Xcode's Run builds it
#   Scripts/install-test-build.sh --mac-installed       the Mac, signed and in /Applications
#   Scripts/install-test-build.sh --simulator <name or UDID>
#
# The options combine, such as --mac --simulator "iPad Air 11-inch (M3)". The simulator is installed
# first and the Mac last, so the Mac apps end up in front.
#
# `xcrun simctl list devices available` shows the simulators. The newest iOS version with that name
# is used.

set -euo pipefail

readonly PROJECT="Hive.xcodeproj"
readonly MAC_APPS=("Hive" "Beekeeper")
readonly SIMULATOR_APP="Beekeeper"

# The real path, without symlinks, so every run reaches the same build folder by the same path, and
# the running copy it quits is matched by the path it was opened from.
cd -P "$(dirname "${BASH_SOURCE[0]}")/.."
readonly REPO_ROOT="$PWD"

fail() {
    echo "error: $*" >&2
    exit 1
}

step() {
    echo
    echo "==> $*"
}

# Prints a pattern for pkill and pgrep that matches a process started from the executable at $1.
# They take a regular expression, and the Debug apps' paths hold parentheses.
process_pattern() {
    printf '^%s' "$(printf '%s' "$1" | sed 's/[][\.*^$()+?{}|]/\\&/g')"
}

# Quits the process started from the executable at $2, and fails naming it $1 if it doesn't.
# Matched by path, so a copy with the same bundle ID elsewhere, such as one running from Xcode, is
# left alone.
quit_process() {
    local label="$1" pattern
    pattern="$(process_pattern "$2")"
    pkill -TERM -f "$pattern" || return 0
    for _ in {1..50}; do
        pgrep -f "$pattern" >/dev/null || return 0
        sleep 0.1
    done
    fail "$label did not quit"
}

# Prints the usage from the comment at the top, and exits with $1.
usage() {
    sed -n '/^# Usage:/,/^#$/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//' >&2
    exit "$1"
}

# Prints the bundle ID of the app at $1.
bundle_id_of() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist"
}

# Waits up to 5 seconds for launchd to finish removing the service $1, such as gui/501/<label>.
wait_for_bootout() {
    for _ in {1..50}; do
        launchctl print "$1" >/dev/null 2>&1 || return 0
        sleep 0.1
    done
    fail "launchd did not stop $1"
}

# Restarts the development daemon from the Debug Hive at $1. The Debug Hive's bundle ID ends in
# .Debug, so the daemon's label and Mach service are its own, never mixing with an installed Hive.
restart_development_daemon() {
    local hive_app="$1"
    local hive_id label plist service
    hive_id="$(bundle_id_of "$hive_app")"
    label="$hive_id.Daemon"
    plist="$REPO_ROOT/build/mac/$label.plist"
    service="gui/$(id -u)/$label"

    "$REPO_ROOT/Scripts/write-launchd-plist.sh" \
        --label "$label" \
        --mach-service "$hive_id.Pairing" \
        --program "$hive_app/Contents/MacOS/HiveDaemon" \
        --output "$plist"

    launchctl bootout "$service" 2>/dev/null || true
    wait_for_bootout "$service"
    launchctl bootstrap "gui/$(id -u)" "$plist"
}

# Installs the app at $1 as $2, owned by root and writable only by root. launchd starts Hive's daemon
# as root from whatever is in the bundle when it's registered, so nothing running as the user may be
# able to change it, and the daemon refuses to start otherwise. Trash can't take a folder the user
# doesn't own, so the old copy is deleted.
install_owned_by_root() {
    local source="$1" destination="$2"
    [[ "$destination" == /Applications/*.app ]] || fail "refusing to replace $destination"
    sudo rm -rf "$destination"
    sudo ditto "$source" "$destination"
    sudo chown -R root:wheel "$destination"
    sudo chmod -R go-w "$destination"
}

check_signing_config() {
    [[ -f "$REPO_ROOT/Configuration/Signing.local.xcconfig" ]] \
        || fail "copy Configuration/Signing.template.xcconfig to Configuration/Signing.local.xcconfig and fill it in"
}

run_on_mac() {
    local derived_data="$REPO_ROOT/build/mac"
    local products="$derived_data/Build/Products/Debug"
    local app

    for app in "${MAC_APPS[@]}"; do
        step "Building $app"
        xcodebuild build \
            -project "$PROJECT" \
            -scheme "$app" \
            -configuration Debug \
            -destination "platform=macOS,arch=$(uname -m)" \
            -derivedDataPath "$derived_data" \
            -allowProvisioningUpdates \
            -quiet
    done

    step "Quitting the copies built last time"
    for app in "${MAC_APPS[@]}"; do
        quit_process "$app built last time" "$products/$app (Debug).app/Contents/MacOS/$app (Debug)"
    done

    step "Restarting the development daemon"
    restart_development_daemon "$products/Hive (Debug).app"

    step "Opening"
    for app in "${MAC_APPS[@]}"; do
        open "$products/$app (Debug).app"
    done

    echo
    echo "Built and opened Debug builds of the working tree."
}

install_on_mac() {
    local work_dir="$REPO_ROOT/build/test-build"
    local app

    step "Checking prerequisites"

    security find-identity -v -p codesigning | grep -q "Developer ID Application" \
        || fail "no Developer ID Application certificate in the keychain"

    command -v trash >/dev/null \
        || fail "the 'trash' command is missing; it ships with macOS 14 and later, or 'brew install trash'"

    rm -rf "$work_dir"
    mkdir -p "$work_dir"

    for app in "${MAC_APPS[@]}"; do
        local archive="$work_dir/$app.xcarchive"
        local export_dir="$work_dir/export-$app"

        step "Archiving $app"
        # TEST_BUILD marks a test build, which released builds never are.
        xcodebuild archive \
            -project "$PROJECT" \
            -scheme "$app" \
            -configuration Release \
            -destination "generic/platform=macOS" \
            -archivePath "$archive" \
            -allowProvisioningUpdates \
            SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) TEST_BUILD'

        step "Exporting a Developer ID build of $app"
        xcodebuild -exportArchive \
            -archivePath "$archive" \
            -exportOptionsPlist "$REPO_ROOT/Scripts/TestBuildExportOptions.plist" \
            -exportPath "$export_dir" \
            -allowProvisioningUpdates

        codesign --verify --deep --strict "$export_dir/$app.app"
    done

    step "Asking for an administrator password, to install Hive owned by root"
    sudo -v

    for app in "${MAC_APPS[@]}"; do
        local installed_app="/Applications/$app.app"

        step "Replacing $installed_app"
        quit_process "the installed $app" "$installed_app/Contents/MacOS/$app"
        if [[ "$app" == "Hive" ]]; then
            install_owned_by_root "$work_dir/export-$app/$app.app" "$installed_app"
        else
            [[ -e "$installed_app" ]] && trash "$installed_app"
            ditto "$work_dir/export-$app/$app.app" "$installed_app"
        fi
    done

    # launchd keeps running the replaced executable until the daemon restarts.
    local daemon_service
    daemon_service="system/$(bundle_id_of /Applications/Hive.app).Daemon"
    if launchctl print "$daemon_service" >/dev/null 2>&1; then
        step "Restarting the daemon"
        sudo launchctl kickstart -k "$daemon_service"
    fi

    step "Opening"
    for app in "${MAC_APPS[@]}"; do
        open "/Applications/$app.app"
    done

    echo
    echo "Installed and opened Developer ID builds of the working tree."
}

# Prints the UDID and name of the simulator to use, separated by a tab. $1 is a device's name or UDID.
choose_simulator() {
    xcrun simctl list devices available --json | /usr/bin/python3 -c '
import json, re, sys

wanted = sys.argv[1]
devices = []
for runtime, entries in json.load(sys.stdin)["devices"].items():
    version = re.search(r"\.iOS-(\d+)-(\d+)$", runtime)
    if version:
        devices += [((int(version[1]), int(version[2])), device) for device in entries]
# Newest iOS first, so a name shared by several versions picks the newest.
devices.sort(key=lambda entry: entry[0], reverse=True)

candidates = [device for _, device in devices if wanted in (device["udid"], device["name"])]
if not candidates:
    sys.exit(1)
print(candidates[0]["udid"] + "\t" + candidates[0]["name"])
' "$1"
}

# Xcode 27 shows simulators in Device Hub, where earlier versions have the Simulator app.
device_hub() {
    echo "$(xcode-select -p)/../Applications/DeviceHub.app"
}

simulator_app() {
    echo "$(xcode-select -p)/Applications/Simulator.app"
}

# Device Hub opens on the device it last showed, saved as JSON: the UDID in quotes. It only reads
# that when it opens, so when it's already open the new simulator is chosen in its sidebar.
select_in_device_hub() {
    if [[ ! -d "$(device_hub)" ]] || pgrep -x DeviceHub >/dev/null; then
        return 0
    fi
    defaults write com.apple.dt.Devices lastSelectedDeviceIdentifier -data "$(printf '"%s"' "$1" | xxd -p | tr -d '\n')"
}

show_simulator() {
    if [[ -d "$(simulator_app)" ]]; then
        open -a "$(simulator_app)" --args -CurrentDeviceUDID "$1"
    elif [[ -d "$(device_hub)" ]]; then
        open -a "$(device_hub)"
    else
        echo "warning: found neither Device Hub nor the Simulator app to show the simulator" >&2
    fi
}

install_on_simulator() {
    local wanted="$1"
    local derived_data="$REPO_ROOT/build/simulator"
    local built_app="$derived_data/Build/Products/Debug-iphonesimulator/$SIMULATOR_APP.app"

    step "Choosing a simulator"
    local chosen udid name
    chosen="$(choose_simulator "$wanted")" || fail "no available iOS simulator matches '$wanted'"
    IFS=$'\t' read -r udid name <<< "$chosen"
    echo "$name ($udid)"

    step "Building"
    xcodebuild build \
        -project "$PROJECT" \
        -scheme "$SIMULATOR_APP" \
        -configuration Debug \
        -destination "id=$udid" \
        -derivedDataPath "$derived_data" \
        -quiet

    # Read from the build, since the bundle ID prefix is set in each clone's own configuration.
    local bundle_id
    bundle_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$built_app/Info.plist")"

    step "Starting $name"
    [[ -d "$(simulator_app)" ]] || select_in_device_hub "$udid"
    xcrun simctl bootstatus "$udid" -b >/dev/null

    step "Installing and launching"
    xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
    xcrun simctl install "$udid" "$built_app"
    xcrun simctl launch "$udid" "$bundle_id" >/dev/null
    show_simulator "$udid"

    echo
    echo "Installed and launched a Debug build of the working tree on $name."
}

[[ $# -gt 0 ]] || usage 0

mac=""
simulators=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mac) mac=debug ;;
        --mac-installed) mac=installed ;;
        --simulator)
            [[ $# -ge 2 ]] || usage 2
            simulators+=("$2")
            shift
            ;;
        *) usage 2 ;;
    esac
    shift
done

[[ -n "$mac" || ${#simulators[@]} -gt 0 ]] || usage 2

check_signing_config

# Hive.app embeds it. Nothing is rebuilt once it's built.
if [[ -n "$mac" ]]; then
    "$REPO_ROOT/Scripts/build-rsync.sh"
fi

for simulator in ${simulators[@]+"${simulators[@]}"}; do
    install_on_simulator "$simulator"
done
case "$mac" in
    debug) run_on_mac ;;
    installed) install_on_mac ;;
esac
