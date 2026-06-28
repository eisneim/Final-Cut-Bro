#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=".build/FCPXLite.app"
BIN=".build/release/FCPXLite"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FCPXLite"
# 应用图标(由 design/new_icon.png 生成的 .icns)
cp design/icons/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>FCPXLite</string>
  <key>CFBundleIdentifier</key><string>com.local.fcpxlite</string>
  <key>CFBundleExecutable</key><string>FCPXLite</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
xattr -cr "$APP"

# Ad-hoc 代码签名:让别人的 Mac 能打开(否则 Gatekeeper 直接拦)。
# 系统框架(AVFoundation/SwiftUI/AppKit/CoreImage)与 Swift 运行时都在 macOS 内,不需打包。
codesign --force --deep --sign - "$APP" 2>/dev/null && echo "ad-hoc 已签名" || echo "签名失败(非致命)"

echo "built $APP"
echo ""
echo "分享给别人:把 $APP 压成 zip 发出去。接收方首次打开:"
echo "  右键 → 打开(绕过 Gatekeeper),或终端跑:xattr -dr com.apple.quarantine /path/to/FCPXLite.app"
