#!/bin/zsh
# Packages Warren.app into a signed, notarized release DMG with an
# /Applications drop link. Uses `diskutil image create` (macOS now
# deprecates the old `hdiutil create` in its favor).
#
# Needs a "Developer ID Application" identity in the keychain and
# notary credentials stored as the keychain profile "warren-notary"
# (xcrun notarytool store-credentials).
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_ID="${WARREN_SIGN_ID:-Developer ID Application}"
NOTARY_PROFILE="${WARREN_NOTARY_PROFILE:-warren-notary}"
if ! security find-identity -v -p codesigning | grep -q "$SIGN_ID"; then
    echo "error: no '$SIGN_ID' identity in the keychain; release DMGs must be signed." >&2
    exit 1
fi

./Scripts/build-app.sh

APP="build/Warren.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGING="build/dmg-staging"
DMG="build/Warren-$VERSION.dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/Warren.app"
ln -s /Applications "$STAGING/Applications"

diskutil image create from --format UDZO --volumeName "Warren $VERSION" "$STAGING" "$DMG"
rm -rf "$STAGING"

codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

echo "Notarizing (this can take a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"

echo "Done: $PWD/$DMG"
