#!/usr/bin/env bash
#
# Downloads Sparkle's command line tools if they are missing, then either runs one of them:
#
#   Scripts/sparkle-tools.sh generate_keys -p
#
# or, given no arguments, prints the directory holding them. Progress goes to stderr, so the path
# is the only thing on stdout.

set -euo pipefail

readonly SPARKLE_VERSION="2.10.0"
readonly SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"

cd "$(dirname "${BASH_SOURCE[0]}")/.."

readonly TOOLS_DIR="$PWD/build/tools"
readonly SPARKLE_DIR="$TOOLS_DIR/Sparkle-$SPARKLE_VERSION"

if [[ ! -x "$SPARKLE_DIR/bin/generate_appcast" ]]; then
    echo "==> Downloading Sparkle $SPARKLE_VERSION tools" >&2
    tarball="$TOOLS_DIR/Sparkle-$SPARKLE_VERSION.tar.xz"
    mkdir -p "$SPARKLE_DIR"
    curl --fail --location --silent --show-error --output "$tarball" \
        "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
    if ! echo "$SPARKLE_SHA256  $tarball" | shasum -a 256 --check --status; then
        rm -rf "$SPARKLE_DIR" "$tarball"
        echo "error: Sparkle tarball does not match the pinned checksum" >&2
        exit 1
    fi
    tar -xJf "$tarball" -C "$SPARKLE_DIR"
fi

if [[ $# -gt 0 ]]; then
    exec "$SPARKLE_DIR/bin/$1" "${@:2}"
fi

echo "$SPARKLE_DIR/bin"
