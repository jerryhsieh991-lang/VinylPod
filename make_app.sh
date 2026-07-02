#!/bin/bash
# Bundles the SPM executable into a runnable macOS .app.
# Needed because we build with Command Line Tools (no Xcode / xcodebuild),
# so `swift build` produces a bare binary, not an app bundle.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="dist/VinylPod.app"
BIN_NAME="VinylPod"

# --- SPM scratch path -------------------------------------------------------
# Keep the .build tree OUT of the repo so iCloud never tries to sync the
# thousands of intermediate object files. Per-checkout subdir so the main
# repo and its worktrees don't clobber each other's caches.
# Override with VINYLPOD_SCRATCH if needed.
CHECKOUT_ID="$(basename "$PWD")-$(printf '%s' "$PWD" | cksum | cut -d' ' -f1)"
SCRATCH="${VINYLPOD_SCRATCH:-$HOME/.cache/vinylpod-build/$CHECKOUT_ID}"

case "$SCRATCH" in
    "$HOME/Desktop/"*|"$HOME/Documents/"*|"$HOME/Library/Mobile Documents/"*)
        echo "✗ scratch path ($SCRATCH) is inside an iCloud-synced folder; refusing." >&2
        exit 1 ;;
esac
mkdir -p "$SCRATCH"

# A leftover in-repo .build is never used (we always pass --scratch-path),
# but it WOULD keep syncing to iCloud — warn so it gets deleted.
if [ -d .build ]; then
    echo "⚠ stale ./.build exists in the repo — delete it: rm -rf \"$PWD/.build\"" >&2
fi

echo "▶ Building ($CONFIG) → scratch: $SCRATCH"
swift build -c "$CONFIG" --scratch-path "$SCRATCH" 2>&1 \
    | grep -Ev "ld: warning|search path" | tail -3

BIN_PATH="$(swift build -c "$CONFIG" --scratch-path "$SCRATCH" --show-bin-path)/$BIN_NAME"
[ -f "$BIN_PATH" ] || { echo "✗ binary not found at $BIN_PATH"; exit 1; }

echo "▶ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"

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
