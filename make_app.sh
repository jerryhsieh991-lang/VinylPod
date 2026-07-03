#!/bin/bash
# Bundles the SPM executable into a runnable macOS .app.
# Needed because we build with Command Line Tools (no Xcode / xcodebuild),
# so `swift build` produces a bare binary, not an app bundle.
set -e
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="dist/VinylPod.app"
BIN_NAME="VinylPod"

echo "▶ Building ($CONFIG)…"
swift build -c "$CONFIG" 2>&1 | grep -Ev "ld: warning|search path" | tail -3

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$BIN_NAME"
[ -f "$BIN_PATH" ] || { echo "✗ binary not found at $BIN_PATH"; exit 1; }

echo "▶ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"

# SPM resource bundle (Bundle.module) — required since Resources/ was added;
# without it the app fatals at launch in resource_bundle_accessor.swift.
RES_BUNDLE="$(dirname "$BIN_PATH")/VinylPod_VinylPod.bundle"
if [ -d "$RES_BUNDLE" ]; then
    cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
else
    echo "✗ resource bundle not found at $RES_BUNDLE"; exit 1
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>VinylPod Widget</string>
    <key>CFBundleDisplayName</key>     <string>VinylPod Widget</string>
    <key>CFBundleIdentifier</key>      <string>com.vinylpod.widget</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>$BIN_NAME</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <!-- Accessory/agent app: lives in the menu bar, no Dock icon. -->
    <key>LSUIElement</key>            <true/>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

# Ad-hoc codesign so macOS will launch it locally.
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  (codesign skipped)"

echo "✓ Built $APP"
echo "  Run:  open \"$APP\"   (look for the ⊙ disc icon in the menu bar)"
