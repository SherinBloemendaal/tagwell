#!/usr/bin/env bash
# Builds build/Tagwell-VERSION.dmg from build/Tagwell.app: the app, an Applications link and the
# drag-to-install background. Run ./build-app.sh first.
#
#   VERSION=1.2.0   names the file Tagwell-1.2.0.dmg and the disk "Tagwell 1.2.0"
#                   (default: the version build-app.sh put in the app)
#
# Uses dmgbuild, which writes the window layout itself, so it works without a Finder session
# (in CI too). It is installed into build/dmgbuild-venv on first use.
set -euo pipefail

cd "$(dirname "$0")/.."

dmgbuild_version="1.6.7"
app="build/Tagwell.app"
[ -d "$app" ] || { echo "make-dmg: $app is missing; run ./build-app.sh first" >&2; exit 1; }

venv="build/dmgbuild-venv"
if [ ! -x "$venv/bin/dmgbuild" ]; then
    python3 -m venv "$venv"
    "$venv/bin/pip" install --quiet "dmgbuild==$dmgbuild_version"
fi

VERSION="${VERSION:-$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")}"
volume_name="Tagwell $VERSION"
dmg="build/Tagwell-$VERSION.dmg"
# One DMG at a time, so a release never picks up an older one.
rm -f build/Tagwell.dmg build/Tagwell-*.dmg
"$venv/bin/dmgbuild" -s scripts/dmg-settings.py -D app="$app" "$volume_name" "$dmg"
echo "Built $dmg"
