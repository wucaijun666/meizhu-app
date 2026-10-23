#!/bin/bash
# 美筑智管 iOS 打包脚本（在 macOS 上运行；GitHub Actions 里会自动调用）
# 产出：美筑智管.ipa（未签名，用 TrollStore 安装）
set -euo pipefail

APP_NAME="MeizhuApp"
DISPLAY_NAME="美筑智管"
BUNDLE_ID="com.meizhu.zhiguan"
MIN_IOS="15.0"
OUT_DIR="build"
APP_DIR="$OUT_DIR/Payload/$APP_NAME.app"

echo "==> 清理"
rm -rf "$OUT_DIR"
mkdir -p "$APP_DIR"

echo "==> 编译（arm64）"
SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || xcrun --sdk iphoneos --show-sdk-path)
clang -arch arm64 \
  -isysroot "$SDK" \
  -miphoneos-version-min="$MIN_IOS" \
  -fobjc-arc \
  -framework UIKit -framework WebKit -framework Foundation \
  -O2 \
  -o "$APP_DIR/$APP_NAME" \
  app/main.m
echo "    编译完成: $(ls -l "$APP_DIR/$APP_NAME" | awk '{print $5}') 字节"

echo "==> 组装 .app"
cp app/Info.plist "$APP_DIR/Info.plist"
cp app/index.html "$APP_DIR/index.html"
for f in app/icons/*.png; do
  [ -e "$f" ] && cp "$f" "$APP_DIR/" || true
done
# PkgInfo（可选）
printf 'APPL????' > "$APP_DIR/PkgInfo"

echo "==> 校验"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_DIR/Info.plist"
file "$APP_DIR/$APP_NAME"

echo "==> 打包 ipa"
cd "$OUT_DIR"
zip -qry "$DISPLAY_NAME.ipa" Payload
cd ..
mv "$OUT_DIR/$DISPLAY_NAME.ipa" "./$DISPLAY_NAME.ipa"
echo "==> 完成: $DISPLAY_NAME.ipa ($(ls -l "$DISPLAY_NAME.ipa" | awk '{print $5}') 字节)"
echo "    用 TrollStore 打开这个 ipa 即可安装"
