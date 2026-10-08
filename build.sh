#!/bin/bash
# Builds "Claude Switcher.app" into ./build
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Claude Switcher.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 Sources/main.swift -o build/ClaudeSwitcher-arm64
swiftc -O -swift-version 5 -target x86_64-apple-macos13.0 Sources/main.swift -o build/ClaudeSwitcher-x86_64
lipo -create build/ClaudeSwitcher-arm64 build/ClaudeSwitcher-x86_64 -output "$APP/Contents/MacOS/ClaudeSwitcher"
rm build/ClaudeSwitcher-arm64 build/ClaudeSwitcher-x86_64
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
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Opens Terminal to run “claude auth login”.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP"
