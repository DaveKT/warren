#!/bin/zsh
# Packages Warren.app into a compressed release DMG with an /Applications
# drop link. Uses `diskutil image create` (macOS now deprecates the old
# `hdiutil create` in its favor).
set -euo pipefail
cd "$(dirname "$0")/.."

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

echo "Done: $PWD/$DMG"
