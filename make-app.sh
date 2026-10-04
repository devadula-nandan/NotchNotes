#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="NotchNotes.app"

# 1. Build an optimized binary
swift build -c release

# 2. Create the app bundle structure
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/NotchNotes "$APP/Contents/MacOS/NotchNotes"

# 3. Info.plist: LSUIElement keeps it out of the Dock and Cmd+Tab
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                <string>NotchNotes</string>
    <key>CFBundleIdentifier</key>          <string>com.local.notchnotes</string>
    <key>CFBundleExecutable</key>          <string>NotchNotes</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>1.0</string>
    <key>CFBundleVersion</key>             <string>1</string>
    <key>LSMinimumSystemVersion</key>      <string>13.0</string>
    <key>LSUIElement</key>                 <true/>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>NSCameraUsageDescription</key>     <string>Web pages you open can ask to use the camera.</string>
    <key>NSMicrophoneUsageDescription</key> <string>Web pages you open can ask to use the microphone.</string>
</dict>
</plist>
EOF

# 4. Ad-hoc sign so macOS runs it without complaint
codesign --force --sign - "$APP"

echo "✅ Built $APP"