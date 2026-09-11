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
    <key>CFBundleIdentifier</key>      <string>com.warren.gopher-browser</string>
    <key>CFBundleExecutable</key>      <string>Warren</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0b</string>
    <key>CFBundleVersion</key>         <string>2</string>
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

# App icon: render the rabbit emoji into an .icns if we can.
if [[ ! -f build/AppIcon.icns ]]; then
    echo "Generating app icon…"
    swift Scripts/makeicon.swift build/icon_1024.png || true
    if [[ -f build/icon_1024.png ]]; then
        ICONSET="build/AppIcon.iconset"
        rm -rf "$ICONSET"; mkdir -p "$ICONSET"
        for size in 16 32 64 128 256 512; do
            sips -z $size $size build/icon_1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
            double=$((size * 2))
            sips -z $double $double build/icon_1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
        done
        iconutil -c icns "$ICONSET" -o build/AppIcon.icns
    fi
fi
[[ -f build/AppIcon.icns ]] && cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# sips/iconutil leave extended attributes behind that codesign rejects.
xattr -cr "$APP"
codesign --force --sign - "$APP"

echo "Done: $PWD/$APP"
