#!/usr/bin/env bash
# Install Tagwell from GitHub releases.
# https://github.com/SherinBloemendaal/tagwell
#
#   curl -fsSL https://raw.githubusercontent.com/SherinBloemendaal/tagwell/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/SherinBloemendaal/tagwell/main/install.sh | bash -s v1.0.0
#
# TAGWELL_VERSION pins a release tag, TAGWELL_INSTALL picks the folder (default /Applications,
# or ~/Applications when /Applications is not writable).

if [ -z "${BASH_VERSION:-}" ]; then
    echo "tagwell: run this script with bash" >&2
    exit 1
fi

set -euo pipefail

repo="SherinBloemendaal/tagwell"
version="${1:-${TAGWELL_VERSION:-latest}}"

fail() {
    echo "tagwell: $*" >&2
    exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "Tagwell is a macOS app."

macos_major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$macos_major" -ge 15 ] || fail "Tagwell needs macOS 15 or later (this Mac runs $(sw_vers -productVersion))."

if pgrep -xq Tagwell; then
    fail "Tagwell is running. Quit it first, then run this script again."
fi

if [ "$version" = "latest" ]; then
    base="https://github.com/$repo/releases/latest/download"
else
    base="https://github.com/$repo/releases/download/$version"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading Tagwell ($version)…"
curl -fsSL "$base/Tagwell.zip" -o "$tmp/Tagwell.zip" || fail "could not download $base/Tagwell.zip"
curl -fsSL "$base/SHA256SUMS" -o "$tmp/SHA256SUMS" || fail "could not download $base/SHA256SUMS"

expected="$(awk '$2 == "Tagwell.zip" { print $1 }' "$tmp/SHA256SUMS")"
actual="$(shasum -a 256 "$tmp/Tagwell.zip" | awk '{ print $1 }')"
[ -n "$expected" ] || fail "SHA256SUMS has no entry for Tagwell.zip"
[ "$expected" = "$actual" ] || fail "checksum mismatch for Tagwell.zip (expected $expected, got $actual)"

ditto -x -k "$tmp/Tagwell.zip" "$tmp/unpacked"
[ -d "$tmp/unpacked/Tagwell.app" ] || fail "the download does not contain Tagwell.app"

destination="${TAGWELL_INSTALL:-/Applications}"
if [ -z "${TAGWELL_INSTALL:-}" ] && [ ! -w "$destination" ]; then
    destination="$HOME/Applications"
fi
mkdir -p "$destination"

rm -rf "$destination/Tagwell.app"
ditto "$tmp/unpacked/Tagwell.app" "$destination/Tagwell.app"
# The app is not notarized. Downloads made by curl are not quarantined, but clear the flag in case.
xattr -dr com.apple.quarantine "$destination/Tagwell.app" 2>/dev/null || true

installed="$(defaults read "$destination/Tagwell.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "$version")"
echo "Installed Tagwell $installed to $destination/Tagwell.app"
echo "Open it with: open \"$destination/Tagwell.app\""
