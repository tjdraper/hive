#!/bin/bash
#
# Builds hive-scout for Linux on x86_64 and aarch64 with Swift's Static Linux SDK, in Docker, checks
# that both binaries are static, runs Scout's tests on Linux, runs each binary once in a container of
# every distribution Scout supports, builds a universal binary for macOS signed with Developer ID, and
# signs a statement of each binary's version, platform and SHA-256. Fails on any warning in Scout's own
# code.
#
# A development build trusts updates signed with Scout's development key, and is signed with it. With
# --release, for Scripts/release.sh, Sparkle's signing key, which also signs the Mac apps' updates. The
# keys' private halves are in the Keychain and their public halves in Configuration/Signing.local.xcconfig
# (Scripts/README.md).
#
# Usage: Scripts/build-scout.sh [--release]
#
# Writes build/scout/linux/:
#   hive-scout-linux-<arch>               the binaries, which Hive.app carries in Contents/Resources/Scout
#   hive-scout-linux-<arch>.statement     their signed statements
#   Scout.xcconfig                        Scout's version and the binaries' hashes, for the apps' Info.plist
#   packages                              the Swift packages the binaries link, for the third-party notices
# and build/scout/macos/:
#   hive-scout-macos-universal            the Mac binary, which Scripts/release.sh notarizes
#   hive-scout-macos-universal.statement  its signed statement

set -euo pipefail

cd -P "$(dirname "$0")/.."

# The Static Linux SDK only works with the exact toolchain it was released with, so the two move together.
# The SDK's checksum is from the archive whose signature checked out against swift.org's release key.
swift_image="swift:6.4.2@sha256:0384f00cf80f81064a907c249a0ad56a1648906f65075a95b1827e88de666e21"
sdk_url="https://download.swift.org/swift-6.4.2-release/static-sdk/swift-6.4.2-RELEASE/swift-6.4.2-RELEASE_static-linux-0.1.0.artifactbundle.tar.gz"
sdk_checksum="3786b179936d9cc9e266dd506bd1654176358d7b25288e243359f4d17cc4dc5a"
sdk_bundle="swift-6.4.2-RELEASE_static-linux-0.1.0"

distributions=(debian:12 ubuntu:24.04 alpine:3.22 rockylinux/rockylinux:9)

key_name="development"
if [[ ${1:-} == --release ]]; then
    key_name="release"
    shift
fi
if [[ $# -ne 0 ]]; then
    echo "usage: Scripts/build-scout.sh [--release]" >&2
    exit 64
fi

out_dir="build/scout"
linux_dir="$out_dir/linux"
macos_dir="$out_dir/macos"
log="$out_dir/build.log"
mkdir -p "$out_dir"

# Volumes rather than folders under build/, since the SDK and SwiftPM's build folders are many small
# files that are much slower through Docker's file sharing with the Mac.
sdk_volume="hive-scout-sdks"
build_volume="hive-scout-build"

stop() {
    echo "error: $*" >&2
    exit 1
}

if ! docker info > /dev/null 2>&1; then
    stop "Docker isn't running"
fi

# Sparkle's tools keep both keys: Sparkle's own under their default account, Scout's development key
# under an account of its own.
if [[ $key_name == release ]]; then
    key_account="ed25519"
    key_setting="UPDATES_PUBLIC_KEY"
else
    key_account="hive-scout-development"
    key_setting="SCOUT_DEVELOPMENT_PUBLIC_KEY"
fi
# Read by hand: base64 can hold "//", which an xcconfig reads as the start of a comment.
public_key=$(sed -n "s/^$key_setting *= *//p" Configuration/Signing.local.xcconfig | tr -d '[:space:]')
[[ -n $public_key ]] || stop "set $key_setting in Configuration/Signing.local.xcconfig (see Scripts/README.md)"
sparkle=$(Scripts/sparkle-tools.sh)
keychain_key=$("$sparkle/generate_keys" --account "$key_account" -p 2> /dev/null) \
    || stop "no $key_name key in the Keychain under the account $key_account (see Scripts/README.md)"
# A build that trusts one key and is signed with another could never be updated.
[[ $keychain_key == "$public_key" ]] \
    || stop "$key_setting in Configuration/Signing.local.xcconfig isn't the public half of the $key_account key in the Keychain"
# A curl download isn't quarantined, so Gatekeeper never checks the Mac binary, but launchd and anyone
# looking at it see who signed it. Release builds are timestamped, which notarization needs.
security find-identity -v -p codesigning | grep -q "Developer ID Application" \
    || stop "no Developer ID Application certificate in the keychain (see Scripts/README.md)"

step() {
    printf '%-24s' "$1"
}

in_swift_container() {
    docker run --rm \
        -v "$PWD/Scout:/scout" \
        -v "$sdk_volume:/sdks" \
        -v "$build_volume:/build" \
        -v "$PWD/$out_dir:/out" \
        -e SCOUT_WARNINGS_AS_ERRORS=1 \
        -e SCOUT_UPDATE_PUBLIC_KEY="$public_key" \
        -w /scout \
        "$swift_image" \
        bash -euo pipefail -c "$1" >> "$log" 2>&1
}

fail() {
    echo "FAILED (log: $log)"
    tail -n 30 "$log" | sed 's/^/    /'
    exit 1
}

: > "$log"
rm -rf "$linux_dir" "$macos_dir"

# Resolved on the Mac first, so Package.resolved keeps the pins only the Mac uses, such as SwiftLint's.
# SwiftPM on Linux would otherwise write it without them after a change to Package.swift.
(cd Scout && swift package resolve --scratch-path ../build/build-and-test/scout) >> "$log" 2>&1 || fail
mkdir -p "$linux_dir"

step "sdk"
in_swift_container "
    swift sdk list --swift-sdks-path /sdks | grep -qx '$sdk_bundle' \
        || swift sdk install '$sdk_url' --checksum '$sdk_checksum' --swift-sdks-path /sdks
" || fail
echo "ok"

for arch in x86_64 aarch64; do
    step "build-$arch"
    in_swift_container "
        swift build -c release --product hive-scout \
            --swift-sdks-path /sdks --swift-sdk $arch-swift-linux-musl \
            --scratch-path /build/$arch \
            -Xlinker --strip-all
        cp \"\$(swift build -c release --swift-sdks-path /sdks --swift-sdk $arch-swift-linux-musl --scratch-path /build/$arch --show-bin-path)/hive-scout\" /out/linux/hive-scout-linux-$arch
    " || fail

    binary="$linux_dir/hive-scout-linux-$arch"
    description=$(file -b "$binary")
    expected_machine=$([[ $arch == x86_64 ]] && echo "x86-64" || echo "ARM aarch64")
    if [[ $description != *"$expected_machine"* || $description != *"statically linked"* ]]; then
        echo "FAILED"
        echo "    not a static $arch binary: $description"
        exit 1
    fi
    if ! LC_ALL=C grep -qF "$public_key" "$binary"; then
        echo "FAILED"
        echo "    the binary doesn't carry the $key_name key, so it would refuse every update"
        exit 1
    fi
    echo "ok ($(du -h "$binary" | cut -f1 | tr -d ' '))"
done

# Static libraries are built only for what the product links, so these are the packages whose
# licenses go with the binaries.
in_swift_container "
    cd /build/x86_64/release
    for module in \$(ls | sed -n 's/\.objlib\$//p'); do
        # Scout's own modules have no checkout.
        for source in /build/x86_64/checkouts/*/Sources/\$module; do
            if [[ -d \$source ]]; then echo \"\$source\" | cut -d/ -f5; fi
        done
    done | sort -u > /out/linux/packages
" || fail

step "tests-linux"
in_swift_container "swift test --scratch-path /build/tests" || fail
echo "ok"

# Every warning SwiftPM prints in Scout's own sources. Dependencies' warnings are suppressed.
problems=$(grep -E '^/scout/(Sources|Tests)/.*(warning|error): ' "$log" | sort -u || true)
if [[ -n "$problems" ]]; then
    echo "warnings:"
    echo "$problems" | sed 's/^/    /'
    exit 1
fi

for distribution in "${distributions[@]}"; do
    for platform in amd64 arm64; do
        arch=$([[ $platform == amd64 ]] && echo x86_64 || echo aarch64)
        step "$(basename "${distribution%%:*}")-${distribution#*:}-$platform"
        if ! sample=$(docker run --rm --platform "linux/$platform" -v "$PWD/$linux_dir:/scout:ro" \
                "$distribution" "/scout/hive-scout-linux-$arch" sample 2>> "$log"); then
            fail
        fi
        echo "ok: $(echo "$sample" | grep '"distribution"' | sed -E 's/.*: "(.*)",?/\1/')"
    done
done

# The private key is exported for the length of the signing, into a folder only this user can read,
# since sign_update can't read it from the Keychain without a password prompt for each key.
sign_dir=$(mktemp -d)
trap 'rm -rf "$sign_dir"' EXIT
(umask 077 && "$sparkle/generate_keys" --account "$key_account" -x "$sign_dir/key" > /dev/null) \
    || stop "couldn't read the $key_account key from the Keychain"

xcconfig="// Written by Scripts/build-scout.sh for the $key_name key. Included by Configuration/Signing.xcconfig."
for arch in x86_64 aarch64; do
    platform=$([[ $arch == x86_64 ]] && echo amd64 || echo arm64)
    binary="$linux_dir/hive-scout-linux-$arch"
    step "statement-$arch"
    # The version and platform the binary reports itself, so the statement can only say what it is.
    status=$(echo '{"request":"status"}' | docker run --rm -i --platform "linux/$platform" -v "$PWD/$linux_dir:/scout:ro" \
        alpine:3.22 "/scout/hive-scout-linux-$arch" manage 2>> "$log") || fail
    version=$(echo "$status" | sed -nE 's/.*"version":"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p')
    reported_platform=$(echo "$status" | sed -nE 's/.*"platform":"([a-z0-9_-]+)".*/\1/p')
    [[ -n $version && $reported_platform == "linux-$arch" ]] || { echo "unexpected status: $status" >> "$log"; fail; }

    hash=$(shasum -a 256 "$binary" | cut -d ' ' -f 1)
    printf 'hive-scout release statement\nversion %s\nplatform %s\nsha256 %s\n' "$version" "$reported_platform" "$hash" > "$sign_dir/signed"
    signature=$("$sparkle/sign_update" --ed-key-file "$sign_dir/key" -p "$sign_dir/signed") || fail
    { cat "$sign_dir/signed"; echo "signature $signature"; } > "$binary.statement"

    upper_arch=$(echo "$arch" | tr '[:lower:]' '[:upper:]')
    xcconfig+=$'\n'"SCOUT_SHA256_LINUX_$upper_arch = $hash"
    echo "ok: $version"
done

step "build-macos"
mkdir -p "$macos_dir"
mac_binary="$macos_dir/hive-scout-macos-universal"
mac_build=(swift build -c release --arch arm64 --arch x86_64 --product hive-scout --scratch-path ../build/scout-macos)
(
    cd Scout
    SCOUT_WARNINGS_AS_ERRORS=1 SCOUT_UPDATE_PUBLIC_KEY="$public_key" "${mac_build[@]}"
    cp "$(SCOUT_UPDATE_PUBLIC_KEY="$public_key" "${mac_build[@]}" --show-bin-path)/hive-scout" "../$mac_binary"
) >> "$log" 2>&1 || fail
problems=$(grep -E "^$PWD/Scout/(Sources|Tests)/.*(warning|error): " "$log" | sort -u || true)
[[ -z "$problems" ]] || { echo "FAILED"; echo "$problems" | sed 's/^/    /'; exit 1; }
[[ $(lipo -archs "$mac_binary") == "x86_64 arm64" ]] || { echo "FAILED"; echo "    not universal: $(lipo -archs "$mac_binary")"; exit 1; }
LC_ALL=C grep -qF "$public_key" "$mac_binary" || { echo "FAILED"; echo "    the binary doesn't carry the $key_name key"; exit 1; }
timestamp=$([[ $key_name == release ]] && echo "--timestamp" || echo "--timestamp=none")
codesign --force --sign "Developer ID Application" --options runtime "$timestamp" \
    --identifier "$(sed -n 's/^ *static let launchdLabel = "\(.*\)"/\1/p' Scout/Sources/ScoutCore/Installing/InstallLayout.swift)" \
    "$mac_binary" >> "$log" 2>&1 || fail
codesign --verify --strict "$mac_binary" >> "$log" 2>&1 || fail
echo "ok ($(du -h "$mac_binary" | cut -f1 | tr -d ' '))"

step "statement-macos"
status=$(echo '{"request":"status"}' | "$mac_binary" manage 2>> "$log") || fail
version=$(echo "$status" | sed -nE 's/.*"version":"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p')
reported_platform=$(echo "$status" | sed -nE 's/.*"platform":"([a-z0-9_-]+)".*/\1/p')
[[ -n $version && $reported_platform == "macos-universal" ]] || { echo "unexpected status: $status" >> "$log"; fail; }
hash=$(shasum -a 256 "$mac_binary" | cut -d ' ' -f 1)
printf 'hive-scout release statement\nversion %s\nplatform %s\nsha256 %s\n' "$version" "$reported_platform" "$hash" > "$sign_dir/signed"
signature=$("$sparkle/sign_update" --ed-key-file "$sign_dir/key" -p "$sign_dir/signed") || fail
{ cat "$sign_dir/signed"; echo "signature $signature"; } > "$mac_binary.statement"
xcconfig+=$'\n'"SCOUT_SHA256_MACOS_UNIVERSAL = $hash"
echo "ok: $version"
rm -rf "$sign_dir"

{
    echo "$xcconfig"
    echo "SCOUT_VERSION = $version"
    echo "SCOUT_UPDATE_KEY = $key_name"
} > "$linux_dir/Scout.xcconfig"
