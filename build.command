#!/bin/zsh
set -eu
cd "${0:A:h}"
destination="${1:-$PWD/build}"
mkdir -p "$destination"
destination="${destination:A}"
app="$destination/ChatGPT网络灯.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 \
  -framework AppKit -framework SwiftUI -framework Network -framework SystemConfiguration \
  Sources/Probe.swift Sources/App.swift Sources/main.swift -o "$app/Contents/MacOS/ChatGPTNetworkLight"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ChatGPTNetworkLight</string>
<key>CFBundleIdentifier</key><string>local.yaosong.chatgpt-network-light</string>
<key>CFBundleName</key><string>ChatGPT网络灯</string>
<key>CFBundleDisplayName</key><string>ChatGPT网络灯</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Local connectivity utility</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
print "已生成：$app"
