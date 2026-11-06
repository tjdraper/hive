#!/bin/bash
#
# Builds Hive for macOS and Beekeeper for macOS and iOS, builds HiveKit for iOS, and runs the HiveKit
# and HiveCore tests. Fails if any step fails or logs a single warning, SwiftLint's included.
#
# Usage: Scripts/build-and-test.sh

set -uo pipefail

# The real path, without symlinks, so every run reaches the same build folder by the same path.
cd -P "$(dirname "$0")/.."

project="Hive.xcodeproj"
build_dir="build/build-and-test"

# Its own derived data, so the warnings-as-errors settings below don't invalidate Xcode's builds.
derived_data="$build_dir/DerivedData"

if [[ ! -f Configuration/Signing.local.xcconfig ]]; then
    echo "error: copy Configuration/Signing.template.xcconfig to Configuration/Signing.local.xcconfig and fill it in" >&2
    exit 1
fi

mkdir -p "$build_dir"

failed=0

run_step() {
    local name="$1"
    shift
    local log="$build_dir/$name.log"

    printf '%-16s' "$name"

    # Treating compiler warnings as errors stops a warning from passing once its file is cached
    # by an incremental build. SwiftLint reruns every build, so the log search catches its warnings.
    # Xcode compiles remote packages with SWIFT_SUPPRESS_WARNINGS, and the compiler refuses that
    # together with warnings as errors, so only targets whose warnings aren't suppressed get it.
    # Beekeeper's keychain access group needs a provisioning profile, which Xcode makes when it's missing.
    xcodebuild "$@" \
        -project "$project" \
        -derivedDataPath "$derived_data" \
        -allowProvisioningUpdates \
        'SWIFT_TREAT_WARNINGS_AS_ERRORS=$(WARNINGS_AS_ERRORS_WHEN_SUPPRESSED_$(SWIFT_SUPPRESS_WARNINGS:default=NO))' \
        WARNINGS_AS_ERRORS_WHEN_SUPPRESSED_NO=YES \
        WARNINGS_AS_ERRORS_WHEN_SUPPRESSED_YES=NO \
        GCC_TREAT_WARNINGS_AS_ERRORS=YES \
        > "$log" 2>&1
    local status=$?

    # Diagnostics start a line or follow a location or tool name. Matching only those skips log
    # messages the tests print, such as a logged "underlyingCoreCryptoError(error: -1)".
    # Xcode logs the App Intents line for every target that doesn't link it. It isn't about our code.
    local problems
    problems=$(grep -E '(^|[[:space:]]|: )(warning|error): ' "$log" \
        | grep -v 'Metadata extraction skipped, no AppIntents.framework dependency found' \
        | sort -u)

    if [[ $status -eq 0 && -z "$problems" ]]; then
        echo "ok"
        return
    fi

    failed=1
    echo "FAILED (log: $log)"
    if [[ -n "$problems" ]]; then
        echo "$problems" | sed 's/^/    /'
    else
        tail -n 20 "$log" | sed 's/^/    /'
    fi
}

run_step hive-macos -scheme Hive -destination "platform=macOS" -configuration Debug build
run_step beekeeper-macos -scheme Beekeeper -destination "platform=macOS" -configuration Debug build
run_step beekeeper-ios -scheme Beekeeper -destination "generic/platform=iOS Simulator" -configuration Debug build
run_step hivekit-ios -scheme HiveKit -destination "generic/platform=iOS Simulator" -configuration Debug build
run_step hivekit-tests -scheme HiveKit -destination "platform=macOS" test
run_step hivecore-tests -scheme HiveCore -destination "platform=macOS" test

exit $failed
