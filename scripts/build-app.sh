#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Reuse a certificate-backed identity so Accessibility grants survive rebuilds.
# Resolve before replacing the installed bundle; never silently fall back to ad-hoc signing.
organiser_identity="${CODE_SIGN_IDENTITY:-}"
if [ -z "$organiser_identity" ]; then
    organiser_identity=$(security find-identity -v -p codesigning | awk '/"Omega Local Signing"/ { print $2; exit }')
fi
if [ -z "$organiser_identity" ]; then
    organiser_identity=$(security find-identity -v -p codesigning | awk '/"Apple Development:/ { print $2; exit }')
fi
if [ -z "$organiser_identity" ]; then
    echo "No stable signing identity found. Set CODE_SIGN_IDENTITY to your development signing identity." >&2
    exit 1
fi
swift build -c release
app="$PWD/dist/Smart Organiser.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/SmartOrganiser "$app/Contents/MacOS/SmartOrganiser"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.smart-organiser</string>
<key>CFBundleName</key><string>Smart Organiser</string>
<key>CFBundleDisplayName</key><string>Smart Organiser</string>
<key>CFBundleExecutable</key><string>SmartOrganiser</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAccessibilityUsageDescription</key><string>Smart Organiser reads, moves, resizes, minimizes, and closes windows to prepare your workspace.</string>
</dict></plist>
PLIST
codesign --force --timestamp=none --sign "$organiser_identity" "$app"
codesign --verify --strict "$app"
echo "Built $app"
