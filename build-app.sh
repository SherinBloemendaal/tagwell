#!/usr/bin/env bash
# Builds Tagwell.app into ./build, ad-hoc signed so it runs on this Mac.
set -euo pipefail

cd "$(dirname "$0")"

swift build -c release --product Tagwell
binary="$(swift build -c release --product Tagwell --show-bin-path)/Tagwell"

app="build/Tagwell.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Tagwell"
cp Resources/Info.plist "$app/Contents/Info.plist"

codesign --force --sign - "$app"
echo "Built $app"
