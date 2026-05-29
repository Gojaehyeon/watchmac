#!/bin/bash
# watchmac.app 만들기 — 실행하면 더블클릭 가능한 메뉴바 앱이 생깁니다.
set -e
cd "$(dirname "$0")"

echo "① 빌드 중… (처음엔 조금 걸려요)"
swift build -c release

BIN=".build/release/watchmac"
APP="watchmac.app"

echo "② 앱 패키징 중…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/watchmac"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                <string>watchmac</string>
    <key>CFBundleDisplayName</key>         <string>watchmac</string>
    <key>CFBundleIdentifier</key>          <string>com.watchmac.app</string>
    <key>CFBundleExecutable</key>          <string>watchmac</string>
    <key>CFBundleVersion</key>             <string>1.0</string>
    <key>CFBundleShortVersionString</key>  <string>1.0</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>LSUIElement</key>                 <true/>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>애플워치에 맥 화면을 표시하기 위해 화면을 캡처합니다.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "③ 완료 → $(pwd)/$APP"
echo
echo "   더블클릭하거나 'open $APP' 으로 실행하세요."
