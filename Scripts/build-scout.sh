#!/bin/bash
#
# Builds hive-scout for Linux on x86_64 and aarch64 with Swift's Static Linux SDK, in Docker, checks
# that both binaries are static, runs Scout's tests on Linux, and runs each binary once in a
# container of every distribution Scout supports. Fails on any warning in Scout's own code.
#
# Usage: Scripts/build-scout.sh
#
# The binaries are written to build/scout/<arch>/hive-scout.

set -euo pipefail

cd -P "$(dirname "$0")/.."

# The Static Linux SDK only works with the exact toolchain it was released with, so the two move together.
# The SDK's checksum is from the archive whose signature checked out against swift.org's release key.
swift_image="swift:6.4.2@sha256:0384f00cf80f81064a907c249a0ad56a1648906f65075a95b1827e88de666e21"
sdk_url="https://download.swift.org/swift-6.4.2-release/static-sdk/swift-6.4.2-RELEASE/swift-6.4.2-RELEASE_static-linux-0.1.0.artifactbundle.tar.gz"
sdk_checksum="3786b179936d9cc9e266dd506bd1654176358d7b25288e243359f4d17cc4dc5a"
sdk_bundle="swift-6.4.2-RELEASE_static-linux-0.1.0"

distributions=(debian:12 ubuntu:24.04 alpine:3.22 rockylinux/rockylinux:9)

out_dir="build/scout"
log="$out_dir/build.log"
mkdir -p "$out_dir"

# Volumes rather than folders under build/, since the SDK and SwiftPM's build folders are many small
# files that are much slower through Docker's file sharing with the Mac.
sdk_volume="hive-scout-sdks"
build_volume="hive-scout-build"

if ! docker info > /dev/null 2>&1; then
    echo "error: Docker isn't running" >&2
    exit 1
fi

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
        mkdir -p /out/$arch
        cp \"\$(swift build -c release --swift-sdks-path /sdks --swift-sdk $arch-swift-linux-musl --scratch-path /build/$arch --show-bin-path)/hive-scout\" /out/$arch/
    " || fail

    description=$(file -b "$out_dir/$arch/hive-scout")
    expected_machine=$([[ $arch == x86_64 ]] && echo "x86-64" || echo "ARM aarch64")
    if [[ $description != *"$expected_machine"* || $description != *"statically linked"* ]]; then
        echo "FAILED"
        echo "    not a static $arch binary: $description"
        exit 1
    fi
    echo "ok ($(du -h "$out_dir/$arch/hive-scout" | cut -f1 | tr -d ' '))"
done

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
        if ! sample=$(docker run --rm --platform "linux/$platform" -v "$PWD/$out_dir/$arch:/scout:ro" \
                "$distribution" /scout/hive-scout sample 2>> "$log"); then
            fail
        fi
        echo "ok: $(echo "$sample" | grep '"distribution"' | sed -E 's/.*: "(.*)",?/\1/')"
    done
done
