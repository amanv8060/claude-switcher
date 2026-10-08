#!/bin/bash
# Builds "Claude Switcher.app" into ./build.
#   ./build.sh            build only
#   ./build.sh --install  also install to ~/Applications, enable launch at login and relaunch
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Claude Switcher.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 Sources/*.swift -o build/ClaudeSwitcher-arm64
swiftc -O -swift-version 5 -target x86_64-apple-macos13.0 Sources/*.swift -o build/ClaudeSwitcher-x86_64
lipo -create build/ClaudeSwitcher-arm64 build/ClaudeSwitcher-x86_64 -output "$APP/Contents/MacOS/ClaudeSwitcher"
rm build/ClaudeSwitcher-arm64 build/ClaudeSwitcher-x86_64
if [ ! -f Resources/AppIcon.icns ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  swift scripts/make-icon.swift "$ICONSET" docs/logo.png
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Claude Switcher</string>
  <key>CFBundleDisplayName</key><string>Claude Switcher</string>
  <key>CFBundleIdentifier</key><string>dev.local.claude-switcher</string>
  <key>CFBundleExecutable</key><string>ClaudeSwitcher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Opens Terminal to run “claude auth login”.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  DEST="$HOME/Applications/Claude Switcher.app"
  pkill -f "Claude Switcher.app/Contents/MacOS/ClaudeSwitcher" 2>/dev/null || true
  sleep 1
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  "$DEST/Contents/MacOS/ClaudeSwitcher" --login-item on
  open "$DEST"
  echo "Installed $DEST"
fi
