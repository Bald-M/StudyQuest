#!/bin/bash
# 构建 release 并打包成 build/StudyQuest.app（仅需 Command Line Tools）
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/StudyQuest.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$BIN_DIR/StudyQuest" "$APP/Contents/MacOS/StudyQuest"
cp "$BIN_DIR/studyquest-mcp" "$APP/Contents/MacOS/studyquest-mcp"
mkdir -p "$APP/Contents/Resources"
cp -R Resources/Web "$APP/Contents/Resources/Web"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>local.studyquest.app</string>
    <key>CFBundleExecutable</key>
    <string>StudyQuest</string>
    <key>CFBundleName</key>
    <string>StudyQuest</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
echo "已生成 $APP"
