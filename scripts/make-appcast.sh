#!/usr/bin/env bash
# Writes dist/appcast.xml, the Sparkle feed Tagwell reads to find this release, and signs both the
# update and the feed with the private key, so Tagwell only installs updates made by this script.
#
#   VERSION=1.3.0          the version being released (required)
#   SPARKLE_PRIVATE_KEY    the private EdDSA key; without it the key is read from 1Password (needs `op`)
#
# Needs dist/Tagwell.zip and a `swift build` that downloaded Sparkle's tools.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${VERSION:?Set VERSION, for example VERSION=1.3.0}"
repo="SherinBloemendaal/tagwell"
zip="dist/Tagwell.zip"
feed="dist/appcast.xml"

sign_update="$(find .build/artifacts -path '*/Sparkle/bin/sign_update' -type f | head -n 1)"
[ -x "$sign_update" ] || { echo "sign_update not found: run swift build first" >&2; exit 1; }
[ -f "$zip" ] || { echo "$zip not found" >&2; exit 1; }

# The key lives only in 1Password; CI gets a copy as the SPARKLE_PRIVATE_KEY secret.
key_item="op://Employee/odlqw22wdffnqd55ieoep3lsem/password"
if [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
    SPARKLE_PRIVATE_KEY="$(op read "$key_item")"
fi

sign() {
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sign_update" --ed-key-file - "$@"
}

escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# What's new: the feat and fix commits since the previous release, without their prefix.
previous="$(git describe --tags --abbrev=0 --match 'v*' "v$VERSION^" 2>/dev/null || true)"
range="${previous:+$previous..}v$VERSION"
notes="$(git log --format=%s "$range" 2>/dev/null \
    | grep -E '^(feat|fix)(\(.+\))?: ' \
    | sed -E 's/^[a-z]+(\([^)]*\))?: //' \
    | escape \
    | perl -pe 's|^(.)(.*)$|<li>\u$1$2</li>|' || true)"
[ -n "$notes" ] || notes="<li>Small improvements.</li>"

signature="$(sign -p "$zip")"
length="$(stat -f %z "$zip")"
minimum="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' Resources/Info.plist)"

cat > "$feed" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Tagwell</title>
    <link>https://github.com/$repo</link>
    <item>
      <title>Tagwell $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/$repo/releases/tag/v$VERSION</sparkle:fullReleaseNotesLink>
      <description><![CDATA[
        <h2>What's new in Tagwell $VERSION</h2>
        <ul>
$notes
        </ul>
      ]]></description>
      <enclosure url="https://github.com/$repo/releases/download/v$VERSION/Tagwell.zip"
                 length="$length" type="application/octet-stream"
                 sparkle:edSignature="$signature"/>
    </item>
  </channel>
</rss>
EOF

sign "$feed"
echo "Wrote $feed"
