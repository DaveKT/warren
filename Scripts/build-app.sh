#!/bin/zsh
# Builds Warren.app from the SwiftPM package.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Building Warren (release)…"
swift build -c release

APP="build/Warren.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Warren "$APP/Contents/MacOS/Warren"

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
    <key>CFBundleShortVersionString</key> <string>1.5b</string>
    <key>CFBundleVersion</key>         <string>7</string>
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

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Copied files can carry extended attributes that codesign rejects.
xattr -cr "$APP"

# Developer ID + hardened runtime (required for notarization) when the
# identity is present; ad-hoc otherwise so dev builds still work.
SIGN_ID="${WARREN_SIGN_ID:-Developer ID Application}"
if security find-identity -v -p codesigning | grep -q "$SIGN_ID"; then
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
    echo "No '$SIGN_ID' identity found; ad-hoc signing (dev build, not for release)."
    codesign --force --sign - "$APP"
fi

echo "Done: $PWD/$APP"
