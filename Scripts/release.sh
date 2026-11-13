#!/usr/bin/env bash
#
# Builds a release of Hive and Beekeeper for the Mac under one version: Developer ID exports of both,
# notarized and stapled, an installer package that puts Hive.app in /Applications owned by root, and the
# Sparkle zips and appcast entries for both apps. Publishing is left to you: the script prints the
# commands at the end.
#
# With --rehearsal, builds the same things for trying an update on this Mac only. It skips the git
# checks, leaves the project and docs/ alone, doesn't notarize, and writes its appcasts under
# build/rehearsal/, for a server on this Mac's loopback address. Rehearse two versions in turn, install
# the first, point the installed apps at the rehearsal feed, and let them update to the second.
#
# With --testflight, archives Beekeeper for iPhone and iPad from the working tree, at the project's
# version and the next build number, and uploads it to TestFlight for internal testers.
#
# One-time setup is in Scripts/README.md.
#
# Usage:
#   Scripts/release.sh <version>                a release to publish, such as 2026.1
#   Scripts/release.sh --rehearsal <version>    a release to try on this Mac
#   Scripts/release.sh --testflight             Beekeeper for iPhone and iPad, to TestFlight
#

set -euo pipefail

readonly PROJECT="Hive.xcodeproj"
readonly APPS=("Hive" "Beekeeper")
readonly GITHUB_REPO="tjdraper/hive"
# The team's App Store Connect API key, shared with the other apps' release scripts.
readonly ASC_OP_ITEM="${HIVE_ASC_OP_ITEM:-op://Private/Apple Developer Account Admin Key}"
readonly ASC_API="https://api.appstoreconnect.apple.com/v1"
# TestFlight builds stop opening this long after they're uploaded.
readonly TESTFLIGHT_DAYS=90
# Sparkle only downloads over HTTP or HTTPS. Plain HTTP is allowed to the loopback address, and every
# update is still checked against the Sparkle signing key.
readonly REHEARSAL_PORT="${HIVE_REHEARSAL_PORT:-8484}"
readonly REHEARSAL_URL="http://127.0.0.1:$REHEARSAL_PORT"

cd -P "$(dirname "${BASH_SOURCE[0]}")/.."
readonly REPO_ROOT="$PWD"
readonly PBXPROJ="$PROJECT/project.pbxproj"

fail() {
    echo "error: $*" >&2
    exit 1
}

step() {
    echo
    echo "==> $*"
}

usage() {
    sed -n '/^# Usage:/,/^#$/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//' >&2
    exit 2
}

# Prints the value of $2 in the Info.plist of the app at $1.
info_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}

# Prints the appcast's file name for the app named $1.
appcast_name() {
    echo "$(echo "$1" | tr '[:upper:]' '[:lower:]').xml"
}

check_signing_config() {
    [[ -f "$REPO_ROOT/Configuration/Signing.local.xcconfig" ]] \
        || fail "copy Configuration/Signing.template.xcconfig to Configuration/Signing.local.xcconfig and fill it in"
}

# Reads the team's App Store Connect API key from 1Password. notarytool and xcodebuild only take the
# key as a file, so it's written somewhere private for the length of the run and removed on the way
# out, however the run ends.
read_asc_key() {
    command -v op >/dev/null || fail "the 1Password CLI is missing; brew install 1password-cli (see Scripts/README.md)"
    asc_key_dir="$(mktemp -d)"
    trap 'rm -rf "$asc_key_dir"' EXIT
    asc_key_id="$(op read "$ASC_OP_ITEM/Key ID")" || fail "couldn't read the Key ID from $ASC_OP_ITEM"
    asc_issuer_id="$(op read "$ASC_OP_ITEM/Issuer ID")" || fail "couldn't read the Issuer ID from $ASC_OP_ITEM"
    asc_key_path="$asc_key_dir/AuthKey_$asc_key_id.p8"
    op read --out-file "$asc_key_path" "$ASC_OP_ITEM/AuthKey_$asc_key_id.p8" >/dev/null \
        || fail "couldn't read AuthKey_$asc_key_id.p8 from $ASC_OP_ITEM"
}

# GETs $1 from the App Store Connect API.
asc_get() {
    local token
    token="$(swift "$REPO_ROOT/Scripts/asc-token.swift" "$asc_key_path" "$asc_key_id" "$asc_issuer_id")" \
        || fail "couldn't sign an App Store Connect API token with the key from $ASC_OP_ITEM"
    curl --silent --show-error --globoff --fail-with-body \
        -H "Authorization: Bearer $token" "$ASC_API$1"
}

send_to_testflight() {
    step "Checking prerequisites"
    check_signing_config
    for tool in jq swift; do
        command -v "$tool" >/dev/null || fail "$tool is missing"
    done
    read_asc_key

    # The project carries the version of the last release, so Beekeeper on iPhone and iPad never
    # tells a Hive it's out of date when no Hive update exists.
    local version
    version="$(grep -oE 'MARKETING_VERSION = [^;]+;' "$PBXPROJ" | sort -u | sed -E 's/.* = (.*);/\1/')"
    [[ "$version" =~ ^[0-9]{4}\.[0-9]+(\.[0-9]+)?$ ]] \
        || fail "the project's MARKETING_VERSION should be one release version, got: $(tr '\n' ' ' <<<"$version")"

    # Read from the project, since the bundle ID prefix is set in each clone's own configuration.
    local bundle_id
    bundle_id="$(xcodebuild -showBuildSettings -project "$PROJECT" -scheme Beekeeper -configuration Release \
        -destination "generic/platform=iOS" 2>/dev/null | awk '$1 == "PRODUCT_BUNDLE_IDENTIFIER" { print $3; exit }')"
    [[ -n "$bundle_id" ]] || fail "couldn't read Beekeeper's bundle ID from the project"

    if [[ -n "$(git status --porcelain)" ]]; then
        echo "The working tree has uncommitted changes. They go into this build."
    fi

    step "Checking App Store Connect"
    local app_json app_id builds_json highest build
    app_json="$(asc_get "/apps?filter[bundleId]=$bundle_id&fields[apps]=name")" \
        || fail "App Store Connect turned down the API key: $app_json"
    app_id="$(jq -r '.data[0].id // empty' <<<"$app_json")"
    [[ -n "$app_id" ]] || fail "App Store Connect has no app with bundle ID $bundle_id (see Scripts/README.md)"

    # Build numbers are a count that goes up with every upload, whatever the version, since a
    # TestFlight build is uploaded again under the same version to replace one about to expire.
    builds_json="$(asc_get "/builds?filter[app]=$app_id&sort=-uploadedDate&fields[builds]=version&limit=200")" \
        || fail "couldn't list Beekeeper's builds: $builds_json"
    highest="$(jq -r '.data[].attributes.version' <<<"$builds_json" | grep -E '^[0-9]+$' | sort -n | tail -1 || true)"
    build=$(( ${highest:-0} + 1 ))

    local work_dir="$REPO_ROOT/build/testflight"
    # Saved where Xcode's Organizer lists it, for its crash reports.
    local archive
    archive="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/Beekeeper $version ($build) iOS.xcarchive"
    local build_date
    build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local auth=(
        -allowProvisioningUpdates
        -authenticationKeyPath "$asc_key_path"
        -authenticationKeyID "$asc_key_id"
        -authenticationKeyIssuerID "$asc_issuer_id"
    )

    rm -rf "$work_dir" "$archive"
    mkdir -p "$work_dir"

    step "Archiving Beekeeper $version ($build) for iPhone and iPad"
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme Beekeeper \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -archivePath "$archive" \
        "${auth[@]}" \
        MARKETING_VERSION="$version" \
        CURRENT_PROJECT_VERSION="$build" \
        BEEKEEPER_BUILD_DATE="$build_date"

    local plist="$archive/Products/Applications/Beekeeper.app/Info.plist"
    [[ "$(plutil -extract CFBundleShortVersionString raw "$plist")" == "$version" ]] || fail "the archive isn't version $version"
    [[ "$(plutil -extract CFBundleVersion raw "$plist")" == "$build" ]] || fail "the archive isn't build $build"
    [[ "$(plutil -extract BeekeeperBuildDate raw "$plist")" == "$build_date" ]] || fail "the archive has no build date"

    echo
    read -r -p "Upload Beekeeper $version ($build) to TestFlight for internal testers? An upload can't be undone. [y/N] " answer
    [[ "$answer" == "y" || "$answer" == "Y" ]] || fail "cancelled; nothing was uploaded"

    # Internal only: Beekeeper is never sent to App Review, and other people build their own.
    cat > "$work_dir/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
	<key>testFlightInternalTestingOnly</key>
	<true/>
</dict>
</plist>
EOF

    step "Uploading to TestFlight"
    xcodebuild -exportArchive \
        -archivePath "$archive" \
        -exportOptionsPlist "$work_dir/ExportOptions.plist" \
        -exportPath "$work_dir/export" \
        "${auth[@]}"

    cat <<EOF

Uploaded Beekeeper $version ($build). It shows in the TestFlight app once Apple has processed it,
and stops opening on $(date -v+"${TESTFLIGHT_DAYS}"d "+%B %-d, %Y").
EOF
}

# --- Arguments -------------------------------------------------------------

rehearsal=""
case "${1:-}" in
    --rehearsal)
        rehearsal=1
        shift
        ;;
    --testflight)
        shift
        [[ $# -eq 0 ]] || usage
        send_to_testflight
        exit 0
        ;;
esac
[[ $# -eq 1 ]] || usage
readonly REHEARSAL="$rehearsal"
readonly VERSION="$1"

# CFBundleVersion is the version too, and Sparkle compares it, so it has to be plain numbers.
[[ "$VERSION" =~ ^[0-9]{4}\.[0-9]+(\.[0-9]+)?$ ]] \
    || fail "the version must be YYYY.N or YYYY.N.P, such as 2026.1, got '$VERSION'"

# Written by hand, and published as-is: embedded in both appcasts and used for the GitHub release.
readonly RELEASE_NOTES_PATH="docs/release-notes/$VERSION.md"
readonly RELEASE_NOTES="$REPO_ROOT/$RELEASE_NOTES_PATH"

if [[ -n "$REHEARSAL" ]]; then
    readonly WORK_DIR="$REPO_ROOT/build/rehearsal/$VERSION"
    readonly APPCAST_DIR="$REPO_ROOT/build/rehearsal/appcasts"
else
    readonly WORK_DIR="$REPO_ROOT/build/release/$VERSION"
    readonly APPCAST_DIR="$REPO_ROOT/docs/appcasts"
fi
readonly OUTPUT_DIR="$WORK_DIR/output"

# --- Preflight -------------------------------------------------------------

step "Checking prerequisites"

check_signing_config

if [[ -z "$REHEARSAL" ]]; then
    # This version's notes may be uncommitted, since they go in with the release commit.
    [[ -z "$(git status --porcelain -uall | grep -v "^?? $RELEASE_NOTES_PATH\$")" ]] \
        || fail "the working tree has changes; commit or stash them first"

    branch="$(git rev-parse --abbrev-ref HEAD)"
    upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" \
        || fail "$branch has no upstream branch, so there is nothing to tag against"

    git fetch --quiet --tags

    # The build number is the version, so a released version can never be rebuilt under the same name.
    ! git rev-parse --verify --quiet "refs/tags/v$VERSION" >/dev/null \
        || fail "v$VERSION is already tagged; pick a new version"

    # The tag has to land on the commit this build came from, so nothing else may be unpushed.
    [[ "$(git rev-list --count "$upstream..HEAD")" == "0" ]] \
        || fail "$branch is ahead of $upstream; push before releasing"
    [[ "$(git rev-list --count "HEAD..$upstream")" == "0" ]] \
        || fail "$branch is behind $upstream; pull before releasing"
fi

identities="$(security find-identity -v -p basic)"
grep -q "Developer ID Application" <<<"$identities" \
    || fail "no Developer ID Application certificate in the keychain (see Scripts/README.md)"

installer_identity=""
if grep -q "Developer ID Installer" <<<"$identities"; then
    installer_identity="Developer ID Installer"
elif [[ -z "$REHEARSAL" ]]; then
    fail "no Developer ID Installer certificate in the keychain (see Scripts/README.md)"
else
    echo "No Developer ID Installer certificate, so the rehearsal's package won't be signed."
fi
readonly INSTALLER_IDENTITY="$installer_identity"

if [[ -z "$REHEARSAL" ]]; then
    read_asc_key
    notary_key=(--key "$asc_key_path" --key-id "$asc_key_id" --issuer "$asc_issuer_id")

    # Apple's reason is the only clue to most refusals, such as an agreement waiting to be accepted.
    if ! notary_check="$(xcrun notarytool history "${notary_key[@]}" --output-format json 2>&1)"; then
        echo "$notary_check" >&2
        fail "Apple's notary service turned down the API key in $ASC_OP_ITEM (see Scripts/README.md)"
    fi
fi

SPARKLE_BIN="$("$REPO_ROOT/Scripts/sparkle-tools.sh")"
readonly SPARKLE_BIN
SPARKLE_PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null)" \
    || fail "no Sparkle signing key in the keychain (see Scripts/README.md)"
readonly SPARKLE_PUBLIC_KEY

# Last, so a run that stops here has already confirmed everything else is in order.
if [[ -z "$REHEARSAL" ]]; then
    if [[ ! -f "$RELEASE_NOTES" ]]; then
        mkdir -p "$(dirname "$RELEASE_NOTES")"
        : > "$RELEASE_NOTES"
        cat <<EOF

Everything else is ready, but $VERSION has no release notes. Write them in the file below and run
this again. They cover both apps, and Sparkle shows them as Markdown in its update window.

$RELEASE_NOTES

EOF
        exit 1
    fi
    [[ -n "$(tr -d '[:space:]' < "$RELEASE_NOTES")" ]] \
        || fail "the release notes are empty; write them before releasing: $RELEASE_NOTES"
fi

# --- Build -----------------------------------------------------------------

rm -rf "$WORK_DIR"
mkdir -p "$OUTPUT_DIR"

step "Building the bundled rsync"
"$REPO_ROOT/Scripts/build-rsync.sh"

if [[ -z "$REHEARSAL" ]]; then
    step "Setting version $VERSION"
    # CFBundleVersion is what Sparkle compares. Keeping it equal to the marketing version leaves one
    # number to reason about, at the cost of needing a new version to rebuild a released one.
    sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"
    sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $VERSION;/g" "$PBXPROJ"
fi

for app in "${APPS[@]}"; do
    step "Archiving $app"
    # The version is also given here, so a rehearsal builds it without changing the project.
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$app" \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -archivePath "$WORK_DIR/$app.xcarchive" \
        -allowProvisioningUpdates \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$VERSION"

    step "Exporting a Developer ID build of $app"
    xcodebuild -exportArchive \
        -archivePath "$WORK_DIR/$app.xcarchive" \
        -exportOptionsPlist "$REPO_ROOT/Scripts/DeveloperIDExportOptions.plist" \
        -exportPath "$WORK_DIR/export-$app" \
        -allowProvisioningUpdates
done

# --- Checks ----------------------------------------------------------------

for app in "${APPS[@]}"; do
    exported="$WORK_DIR/export-$app/$app.app"
    step "Checking $app"

    codesign --verify --deep --strict "$exported"
    signature="$(codesign --display --verbose=2 "$exported" 2>&1)"
    grep -q "flags=.*runtime" <<<"$signature" || fail "$app isn't signed with the hardened runtime"
    grep -q "Developer ID Application" <<<"$signature" || fail "$app isn't signed with a Developer ID Application certificate"

    [[ "$(info_value "$exported" CFBundleShortVersionString)" == "$VERSION" ]] || fail "$app isn't version $VERSION"
    [[ "$(info_value "$exported" CFBundleVersion)" == "$VERSION" ]] || fail "$app's build number isn't $VERSION"

    # A build without these never updates, and one with another key refuses every update it's offered.
    [[ "$(info_value "$exported" SUPublicEDKey)" == "$SPARKLE_PUBLIC_KEY" ]] \
        || fail "$app's SUPublicEDKey doesn't match the Sparkle key in the keychain; check UPDATES_PUBLIC_KEY in Configuration/Signing.local.xcconfig"
    feed="$(info_value "$exported" SUFeedURL)"
    [[ "$feed" =~ ^https://[^/]+/.+/$(appcast_name "$app")$ ]] \
        || fail "$app's feed is '$feed'; check UPDATES_SITE in Configuration/Signing.local.xcconfig"
done

hive_app="$WORK_DIR/export-Hive/Hive.app"
for embedded in "Contents/MacOS/HiveDaemon" "Contents/MacOS/rsync"; do
    signature="$(codesign --display --verbose=2 "$hive_app/$embedded" 2>&1)"
    grep -q "flags=.*runtime" <<<"$signature" || fail "$embedded in Hive.app isn't signed with the hardened runtime"
done
# The daemon refuses to start from a bundle that anyone but root can change. The installer and Sparkle
# make root the owner, but keep each file's permissions.
writable="$(find "$hive_app" -perm -g+w -o -perm -o+w)"
[[ -z "$writable" ]] || fail "files in Hive.app are writable by others than their owner:
$writable"

# --- Notarize --------------------------------------------------------------

if [[ -z "$REHEARSAL" ]]; then
    for app in "${APPS[@]}"; do
        exported="$WORK_DIR/export-$app/$app.app"
        submission="$WORK_DIR/$app-notarization.zip"

        step "Notarizing $app (this waits for Apple)"
        # Plain `zip` drops the symlinks and extended attributes that a signed bundle needs.
        ditto -c -k --keepParent "$exported" "$submission"
        xcrun notarytool submit "$submission" "${notary_key[@]}" --wait

        step "Stapling $app"
        xcrun stapler staple "$exported"
        xcrun stapler validate "$exported"
        spctl --assess --type exec --verbose=2 "$exported"
    done
fi

# --- Installer package -----------------------------------------------------

hive_id="$(info_value "$hive_app" CFBundleIdentifier)"
readonly PACKAGE="$OUTPUT_DIR/Hive-$VERSION.pkg"

step "Building Hive's installer package"
package_root="$WORK_DIR/package-root"
ditto "$hive_app" "$package_root/Hive.app"
pkgbuild --analyze --root "$package_root" "$WORK_DIR/components.plist" >/dev/null
# A relocatable bundle is installed over any copy of Hive.app the Mac knows of, wherever it is. Hive
# only runs from /Applications, owned by root.
/usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$WORK_DIR/components.plist"
pkgbuild \
    --root "$package_root" \
    --component-plist "$WORK_DIR/components.plist" \
    --install-location /Applications \
    --identifier "$hive_id.pkg" \
    --version "$VERSION" \
    --ownership recommended \
    "$WORK_DIR/Hive-component.pkg"

signing=()
[[ -n "$INSTALLER_IDENTITY" ]] && signing=(--sign "$INSTALLER_IDENTITY")
# The +"..." guard is for bash 3.2, which treats an empty array as unset under `set -u`.
productbuild --package "$WORK_DIR/Hive-component.pkg" ${signing[@]+"${signing[@]}"} "$PACKAGE"

pkgutil --expand "$WORK_DIR/Hive-component.pkg" "$WORK_DIR/package-check"
owners="$(lsbom -p ug "$WORK_DIR/package-check/Bom" | sort -u)"
[[ "$owners" == $'0\t0' ]] || fail "the package doesn't install everything owned by root:wheel"

if [[ -z "$REHEARSAL" ]]; then
    step "Notarizing the package (this waits for Apple)"
    xcrun notarytool submit "$PACKAGE" "${notary_key[@]}" --wait
    xcrun stapler staple "$PACKAGE"
    xcrun stapler validate "$PACKAGE"
    spctl --assess --type install --verbose=2 "$PACKAGE"
fi

# --- Appcasts --------------------------------------------------------------

mkdir -p "$APPCAST_DIR"
for app in "${APPS[@]}"; do
    exported="$WORK_DIR/export-$app/$app.app"
    stage="$WORK_DIR/appcast-$app"
    zip="$stage/$app-$VERSION.zip"
    appcast="$APPCAST_DIR/$(appcast_name "$app")"

    step "Adding $app to its appcast"
    mkdir -p "$stage"
    # The ticket has to be inside the zip Sparkle downloads, so it's made from the stapled app.
    ditto -c -k --keepParent "$exported" "$zip"
    # generate_appcast pairs notes with an archive by file name, and keeps the items already in the appcast.
    if [[ -n "$REHEARSAL" ]]; then
        echo "Rehearsal of $VERSION." > "$stage/$app-$VERSION.md"
        download_prefix="$REHEARSAL_URL/$VERSION/appcast-$app/"
    else
        cp "$RELEASE_NOTES" "$stage/$app-$VERSION.md"
        download_prefix="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/"
    fi
    [[ -f "$appcast" ]] && cp "$appcast" "$stage/appcast.xml"

    "$SPARKLE_BIN/generate_appcast" \
        --download-url-prefix "$download_prefix" \
        --embed-release-notes \
        --link "https://github.com/$GITHUB_REPO" \
        -o "$stage/appcast.xml" \
        "$stage"

    cp "$stage/appcast.xml" "$appcast"
    cp "$zip" "$OUTPUT_DIR/"
done

# --- Next steps ------------------------------------------------------------

beekeeper_id="$(info_value "$WORK_DIR/export-Beekeeper/Beekeeper.app" CFBundleIdentifier)"

if [[ -n "$REHEARSAL" ]]; then
    cat <<EOF

Built rehearsal $VERSION in $OUTPUT_DIR. Nothing was notarized, committed or published.

To install it, as a first install would:

  sudo installer -pkg "$PACKAGE" -target /
  ditto "$WORK_DIR/export-Beekeeper/Beekeeper.app" /Applications/Beekeeper.app

To have the installed apps update from the rehearsal appcasts instead of the published ones, serve
them on this Mac's loopback address while you try the update:

  python3 -m http.server --bind 127.0.0.1 --directory "$REPO_ROOT/build/rehearsal" $REHEARSAL_PORT
  defaults write $hive_id SUFeedURL "$REHEARSAL_URL/appcasts/$(appcast_name Hive)"
  defaults write $beekeeper_id SUFeedURL "$REHEARSAL_URL/appcasts/$(appcast_name Beekeeper)"

and to go back to the published ones:

  defaults delete $hive_id SUFeedURL
  defaults delete $beekeeper_id SUFeedURL
EOF
    exit 0
fi

cat <<EOF

Built and notarized Hive and Beekeeper $VERSION.

  $PACKAGE
  $OUTPUT_DIR/Hive-$VERSION.zip
  $OUTPUT_DIR/Beekeeper-$VERSION.zip

Publish in this order. The tag lands on the release commit, and the downloads go live before the
appcasts point at them:

  git add "$PBXPROJ" docs && git commit -m "Release $VERSION"
  git tag v$VERSION
  git push origin v$VERSION
  gh release create v$VERSION "$PACKAGE" "$OUTPUT_DIR/Hive-$VERSION.zip" "$OUTPUT_DIR/Beekeeper-$VERSION.zip" --repo $GITHUB_REPO --title "$VERSION" --verify-tag --notes-file $RELEASE_NOTES_PATH
  git push

Then send Beekeeper $VERSION for iPhone and iPad to TestFlight from the release commit:

  Scripts/release.sh --testflight

If you stop here, undo the version and the appcast entries with:

  git checkout -- "$PBXPROJ" docs/appcasts
EOF
