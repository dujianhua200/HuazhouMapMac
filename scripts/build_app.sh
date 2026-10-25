#!/usr/bin/env bash
# 构建 macOS 原生 .app 包（SwiftPM 产物 + Info.plist + ad-hoc 签名）
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="滑洲云图"
BUNDLE_ID="com.huazhou.map"
VERSION="2.0.1"
BUILD_NUMBER="1"
MIN_MACOS="13.0"

echo "==> 编译 ($CONFIG)"
swift build -c "$CONFIG" --disable-sandbox
BIN_PATH="$(swift build -c "$CONFIG" --disable-sandbox --show-bin-path)"

APP_DIR="$ROOT/dist/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH/HuazhouMap" "$APP_DIR/Contents/MacOS/HuazhouMap"
chmod +x "$APP_DIR/Contents/MacOS/HuazhouMap"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleExecutable</key>
	<string>HuazhouMap</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>${APP_NAME} Mac</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD_NUMBER}</string>
	<key>LSMinimumSystemVersion</key>
	<string>${MIN_MACOS}</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSSupportsAutomaticTermination</key>
	<true/>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>滑洲云图工程</string>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>LSHandlerRank</key>
			<string>Owner</string>
			<key>CFBundleTypeExtensions</key>
			<array>
				<string>hzmap</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST

echo "==> 校验 Info.plist"
plutil -lint "$APP_DIR/Contents/Info.plist"

echo "==> 代码签名（ad-hoc）"
codesign --force --sign - "$APP_DIR" 2>/dev/null || echo "ad-hoc 签名跳过（不影响本地运行）"

echo "==> 打包 zip"
mkdir -p "$ROOT/dist"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ROOT/dist/HuazhouMap-macOS.zip"

echo ""
echo "完成：$APP_DIR"
echo "压缩包：$ROOT/dist/HuazhouMap-macOS.zip"
