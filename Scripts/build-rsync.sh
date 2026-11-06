#!/bin/bash
#
# Builds the rsync that Hive bundles, from source at a fixed version, for Apple silicon and Intel.
# macOS's own openrsync can't tell a file that vanished mid-run from a real failure and has no
# --fake-super (Plans/HighLevelPlan/00-Info.md §11).
#
# The download is checked against the SHA-256 below before anything is built. The checksum was taken
# from a tarball whose OpenPGP signature verified against the release key rsync.samba.org lists. To
# move to another version, verify its signature the same way and replace both values.
#
# The result is build/rsync/rsync. Nothing is rebuilt while it matches the version and checksum here.
# The Hive target embeds it in Hive.app and signs it, and HiveCore's tests run it.
#
# Usage: Scripts/build-rsync.sh

set -euo pipefail

readonly VERSION="3.5.2"
readonly SHA256="a10d591825251e070f74c98df3daad195def4ed81b4a2de16169026aea33f6c8"
readonly SOURCE_URL="https://download.samba.org/pub/rsync/src/rsync-$VERSION.tar.gz"
readonly ARCHITECTURES=(arm64 x86_64)
readonly DEPLOYMENT_TARGET="26.0"

cd -P "$(dirname "$0")/.."
readonly OUTPUT_DIR="$PWD/build/rsync"
readonly STAMP="$OUTPUT_DIR/built-from"
readonly WORK_DIR="$OUTPUT_DIR/work"
readonly TARBALL="$OUTPUT_DIR/rsync-$VERSION.tar.gz"

fail() {
    echo "error: $*" >&2
    exit 1
}

if [[ -x "$OUTPUT_DIR/rsync" && "$(cat "$STAMP" 2>/dev/null)" == "$VERSION $SHA256" ]]; then
    echo "rsync $VERSION is already built: $OUTPUT_DIR/rsync"
    exit 0
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$WORK_DIR" "$OUTPUT_DIR/rsync" "$STAMP"
mkdir -p "$WORK_DIR"

if [[ ! -f "$TARBALL" ]] || ! echo "$SHA256  $TARBALL" | shasum -a 256 -c --status; then
    echo "Downloading rsync $VERSION"
    curl --fail --silent --show-error --location --output "$TARBALL.download" "$SOURCE_URL"
    mv "$TARBALL.download" "$TARBALL"
fi
echo "$SHA256  $TARBALL" | shasum -a 256 -c --status \
    || fail "rsync-$VERSION.tar.gz doesn't match its checksum; delete $TARBALL and try again"

host_architecture="$(uname -m)"
slices=()
for architecture in "${ARCHITECTURES[@]}"; do
    echo "Building rsync $VERSION for $architecture"
    source_dir="$WORK_DIR/$architecture"
    mkdir -p "$source_dir"
    tar -xzf "$TARBALL" -C "$source_dir" --strip-components 1

    # Naming the host makes configure cross-compile for the other architecture, using its defaults
    # rather than running test programs that this Mac can't run.
    cross_compiling=()
    if [[ "$architecture" != "$host_architecture" ]]; then
        cross_compiling=(--host="$architecture-apple-darwin" --build="$host_architecture-apple-darwin")
    fi

    # Only extended attributes are needed beyond the basics, for --fake-super. Everything optional
    # that would reach for a library outside macOS is left out, so the build is the same on every Mac.
    (
        cd "$source_dir"
        CC="clang -arch $architecture" \
            CFLAGS="-O2 -mmacosx-version-min=$DEPLOYMENT_TARGET" \
            LDFLAGS="-mmacosx-version-min=$DEPLOYMENT_TARGET" \
            ./configure "${cross_compiling[@]+"${cross_compiling[@]}"}" \
            --enable-xattr-support \
            --disable-openssl \
            --disable-xxhash \
            --disable-zstd \
            --disable-lz4 \
            --disable-iconv \
            --disable-idn \
            --disable-md2man \
            --with-included-popt \
            --with-included-zlib \
            > configure.log 2>&1 || { tail -n 30 configure.log >&2; fail "configure failed for $architecture"; }
        make -j "$(sysctl -n hw.ncpu)" rsync > make.log 2>&1 || { tail -n 30 make.log >&2; fail "make failed for $architecture"; }
    )
    grep -q '^#define SUPPORT_XATTRS 1' "$source_dir/config.h" || fail "rsync for $architecture was built without extended attributes"
    slices+=("$source_dir/rsync")
done

lipo -create "${slices[@]}" -output "$OUTPUT_DIR/rsync"
# Ad hoc, so tests can run it. The Hive target signs its own copy with Hive's identity, keeping this
# identifier rather than the hash the linker gives an unnamed program.
codesign --force --sign - --identifier org.samba.rsync "$OUTPUT_DIR/rsync"
echo "$VERSION $SHA256" > "$STAMP"

"$OUTPUT_DIR/rsync" --version | head -n 1
echo "Built $OUTPUT_DIR/rsync ($(lipo -archs "$OUTPUT_DIR/rsync"))"
