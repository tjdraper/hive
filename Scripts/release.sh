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
# One-time setup is in Scripts/README.md.
#
# Usage:
#   Scripts/release.sh <version>                a release to publish, such as 2026.1
#   Scripts/release.sh --rehearsal <version>    a release to try on this Mac
#

set -euo pipefail

readonly PROJECT="Hive.xcodeproj"
readonly APPS=("Hive" "Beekeeper")
readonly GITHUB_REPO="tjdraper/hive"
# The team's App Store Connect API key, shared with the other apps' release scripts.
readonly ASC_OP_ITEM="${HIVE_ASC_OP_ITEM:-op://Private/Apple Developer Account Admin Key}"
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

# --- Arguments -------------------------------------------------------------

rehearsal=""
if [[ "${1:-}" == "--rehearsal" ]]; then
    rehearsal=1
    shift
fi
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

[[ -f "$REPO_ROOT/Configuration/Signing.local.xcconfig" ]] \
    || fail "copy Configuration/Signing.template.xcconfig to Configuration/Signing.local.xcconfig and fill it in"

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
    command -v op >/dev/null || fail "the 1Password CLI is missing; brew install 1password-cli (see Scripts/README.md)"

    # notarytool only takes the key as a file, so it's written somewhere private for the length of
    # the run and removed on the way out, however the run ends.
    asc_key_dir="$(mktemp -d)"
    trap 'rm -rf "$asc_key_dir"' EXIT
    asc_key_id="$(op read "$ASC_OP_ITEM/Key ID")" || fail "couldn't read the Key ID from $ASC_OP_ITEM"
    asc_issuer_id="$(op read "$ASC_OP_ITEM/Issuer ID")" || fail "couldn't read the Issuer ID from $ASC_OP_ITEM"
    asc_key_path="$asc_key_dir/AuthKey_$asc_key_id.p8"
    op read --out-file "$asc_key_path" "$ASC_OP_ITEM/AuthKey_$asc_key_id.p8" >/dev/null \
        || fail "couldn't read AuthKey_$asc_key_id.p8 from $ASC_OP_ITEM"
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

If you stop here, undo the version and the appcast entries with:

  git checkout -- "$PBXPROJ" docs/appcasts
EOF
