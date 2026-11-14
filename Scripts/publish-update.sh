#!/bin/zsh
# Adds a release to the Sparkle update feed (appcast.xml at the repo root).
#
# Run after make-dmg.sh, with the release notes as a Markdown file (the
# same text as the GitHub release body):
#
#   ./Scripts/publish-update.sh notes.md
#
# The update is signed with the private EdDSA key in the login keychain
# (created once with Sparkle's generate_keys; its public half is
# SPARKLE_PUBLIC_KEY in build-app.sh). WARREN_ED_KEY_FILE can point to a
# key file instead, for testing.
#
# Then, in this order:
#   1. Create the GitHub release v<version> with the DMG attached.
#   2. Commit and push appcast.xml. Installed copies see the update once
#      the pushed feed is live (GitHub may cache it for a few minutes).
set -euo pipefail
cd "$(dirname "$0")/.."

NOTES="${1:-}"
if [[ -z "$NOTES" || ! -f "$NOTES" ]]; then
    echo "usage: $0 <release-notes.md>" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/Warren.app/Contents/Info.plist)
DMG="build/Warren-$VERSION.dmg"
if [[ ! -f "$DMG" ]]; then
    echo "error: $DMG not found; run ./Scripts/make-dmg.sh first." >&2
    exit 1
fi

BIN=".build/artifacts/sparkle/Sparkle/bin"
REPO_URL="https://github.com/DaveKT/warren"
STAGING="build/appcast"

# generate_appcast works on a folder holding the existing feed plus the
# new archive, and its release notes under the archive's name.
rm -rf "$STAGING"
mkdir -p "$STAGING"
[[ -f appcast.xml ]] && cp appcast.xml "$STAGING/appcast.xml"
cp "$DMG" "$STAGING/"
cp "$NOTES" "$STAGING/Warren-$VERSION.md"

KEY_ARGS=()
[[ -n "${WARREN_ED_KEY_FILE:-}" ]] && KEY_ARGS=(--ed-key-file "$WARREN_ED_KEY_FILE")

"$BIN/generate_appcast" "${KEY_ARGS[@]}" \
    --download-url-prefix "$REPO_URL/releases/download/v$VERSION/" \
    --full-release-notes-url "$REPO_URL/releases/tag/v$VERSION" \
    --link "$REPO_URL" \
    --embed-release-notes \
    "$STAGING"

# generate_appcast leaves the update unsigned (and installed copies would
# refuse it) if the app has no SUPublicEDKey; it errors if the key
# doesn't match the private key.
if ! grep -q "releases/download/v$VERSION/Warren-$VERSION.dmg\".*sparkle:edSignature=" "$STAGING/appcast.xml"; then
    echo "error: the update for $VERSION wasn't signed. Is SPARKLE_PUBLIC_KEY set in build-app.sh?" >&2
    exit 1
fi

cp "$STAGING/appcast.xml" appcast.xml
echo "Updated appcast.xml with Warren $VERSION."
echo "Next: create the GitHub release v$VERSION with $DMG attached, then commit and push appcast.xml."
