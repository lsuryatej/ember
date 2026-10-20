#!/bin/bash
set -euo pipefail

# Renders the menu in each state, light and dark, into a folder of PNGs.
#
#   ./screenshots.sh [output directory]     (default: screenshots/)

cd "$(dirname "$0")"

find_developer_dir() {
    for candidate in \
        "/Applications/Xcode-beta.app/Contents/Developer" \
        "/Applications/Xcode.app/Contents/Developer" \
        "$HOME/Downloads/Xcode-beta.app/Contents/Developer"
    do
        [ -x "$candidate/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" ] && echo "$candidate" && return 0
    done
    return 1
}
DEVELOPER_DIR="$(find_developer_dir)" || { echo "error: no Xcode toolchain found." >&2; exit 1; }
export DEVELOPER_DIR
SWIFTC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
SDK="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

OUT="${1:-screenshots}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SOURCES=()
for file in src/*.swift; do
    [ "$file" = "src/main.swift" ] || SOURCES+=("$file")
done
"$SWIFTC" -sdk "$SDK" -target "$(uname -m)-apple-macos14.0" "${SOURCES[@]}" tools/screenshots/main.swift -o "$WORK/EmberScreenshots"
"$WORK/EmberScreenshots" "$OUT"
