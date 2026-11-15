#!/bin/zsh
# Builds Warren.app from the SwiftPM package.
set -euo pipefail
cd "$(dirname "$0")/.."

# Automatic updates (Sparkle). The app reads the feed below and only
# installs updates signed with the private key matching this public key,
# which lives in the release machine's login keychain (see
# Scripts/publish-update.sh).
SPARKLE_FEED_URL="https://raw.githubusercontent.com/DaveKT/warren/main/appcast.xml"
SPARKLE_PUBLIC_KEY="nzsJcGM2RDDgIy+BGDNCfWiRl20yHoSU5kllNgLjhrk="

echo "Building Warren (release)…"
swift build -c release

APP="build/Warren.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/release/Warren "$APP/Contents/MacOS/Warren"
# ditto keeps the framework's internal symlinks intact.
ditto .build/release/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Warren</string>
    <key>CFBundleDisplayName</key>     <string>Warren</string>
    <key>CFBundleIdentifier</key>      <string>app.warren1436.Warren</string>
    <key>CFBundleExecutable</key>      <string>Warren</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.8b</string>
    <key>CFBundleVersion</key>         <string>10</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSSupportsAutomaticTermination</key> <false/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key> <string>Gopher</string>
            <key>CFBundleURLSchemes</key>
            <array><string>gopher</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$PLIST"
if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$PLIST"
else
    echo "warning: SPARKLE_PUBLIC_KEY is empty; this build can't check for updates."
fi

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Copied files can carry extended attributes that codesign rejects.
xattr -cr "$APP"

# Developer ID + hardened runtime (required for notarization) when the
# identity is present; ad-hoc otherwise so dev builds still work.
SIGN_ID="${WARREN_SIGN_ID:-Developer ID Application}"
if security find-identity -v -p codesigning | grep -q "$SIGN_ID"; then
    SIGN=(codesign --force --options runtime --timestamp --sign "$SIGN_ID")
else
    echo "No '$SIGN_ID' identity found; ad-hoc signing (dev build, not for release)."
    SIGN=(codesign --force --sign -)
fi

# Sign from the inside out: Sparkle's helpers, then the framework, then
# the app. Sparkle ships signed by its own team, but the hardened runtime
# only loads frameworks signed by the app's team, so it's re-signed here.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
"${SIGN[@]}" "$SPARKLE/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"

echo "Done: $PWD/$APP"
