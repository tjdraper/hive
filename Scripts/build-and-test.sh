#!/bin/bash
#
# Builds the bundled rsync if it isn't yet, Hive for macOS and Beekeeper for macOS and iOS, builds
# HiveKit for iOS, and runs the HiveKit, HiveCore and Scout tests. Builds Scout for Linux in Docker
# when Scout changed since that last passed. Fails if any step fails or logs a single warning,
# SwiftLint's included, or if the apps' third-party notices don't match what they link.
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

# Hive.app embeds it and HiveCore's tests run it. Nothing is rebuilt once it's built.
Scripts/build-rsync.sh > "$build_dir/rsync.log" 2>&1 || { tail -n 20 "$build_dir/rsync.log" >&2; exit 1; }

failed=0

report() {
    local name="$1" status="$2"
    local log="$build_dir/$name.log"

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
    report "$name" $?
}

run_step hive-macos -scheme Hive -destination "platform=macOS" -configuration Debug build
run_step beekeeper-macos -scheme Beekeeper -destination "platform=macOS" -configuration Debug build
run_step beekeeper-ios -scheme Beekeeper -destination "generic/platform=iOS Simulator" -configuration Debug build
run_step hivekit-ios -scheme HiveKit -destination "generic/platform=iOS Simulator" -configuration Debug build
run_step hivekit-tests -scheme HiveKit -destination "platform=macOS" test
run_step hivecore-tests -scheme HiveCore -destination "platform=macOS" test

# Scout is a package of its own, built by SwiftPM. SCOUT_WARNINGS_AS_ERRORS stands in for the
# warnings-as-errors settings above. SwiftPM shows SwiftLint's warnings only when it reruns the plugin,
# which an incremental build skips, so SwiftLint also runs on its own, with the plugin's binary.
printf '%-16s' "scout-tests"
(cd Scout && SCOUT_WARNINGS_AS_ERRORS=1 swift test --scratch-path "../$build_dir/scout") > "$build_dir/scout-tests.log" 2>&1
report scout-tests $?

printf '%-16s' "scout-lint"
swiftlint="$build_dir/scout/artifacts/swiftlintplugins/SwiftLintBinary/SwiftLintBinary.artifactbundle/macos/swiftlint"
if [[ -x $swiftlint ]]; then
    "$swiftlint" lint --quiet Scout/Sources Scout/Tests > "$build_dir/scout-lint.log" 2>&1
    report scout-lint $?
else
    failed=1
    echo "FAILED: SwiftLint wasn't fetched by the Scout build"
fi

# The Linux build needs Docker and takes minutes, so it runs only when Scout changed since it last passed.
printf '%-16s' "scout-linux"
scout_fingerprint=$(git ls-files -z -co --exclude-standard -- Scout Scripts/build-scout.sh \
    | xargs -0 shasum -a 256 2> /dev/null | shasum -a 256 | cut -d' ' -f1)
scout_passed="$build_dir/scout-linux.passed"
if [[ -f $scout_passed && $(cat "$scout_passed") == "$scout_fingerprint" ]]; then
    echo "unchanged"
elif Scripts/build-scout.sh > "$build_dir/scout-linux.log" 2>&1; then
    echo "$scout_fingerprint" > "$scout_passed"
    echo "ok"
else
    failed=1
    echo "FAILED (log: $build_dir/scout-linux.log)"
    tail -n 20 "$build_dir/scout-linux.log" | sed 's/^/    /'
fi

# Reads what the builds above linked, so only a run whose builds all passed can check it.
printf '%-16s' "notices"
if [[ $failed -ne 0 ]]; then
    echo "skipped"
elif notices_problem=$(Scripts/write-third-party-notices.sh --check 2>&1); then
    echo "ok"
else
    failed=1
    echo "FAILED"
    echo "$notices_problem" | sed 's/^/    /'
fi

exit $failed
