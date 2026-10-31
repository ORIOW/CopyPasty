#!/bin/bash
# CopyPasty DMG 打包脚本（无需 Apple Developer Program）
# 用法: ./Scripts/make_dmg.sh
# 产物: build/CopyPasty-<版本>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

# 本机 xcode-select 指向 CommandLineTools 时自动改用完整 Xcode（已设 DEVELOPER_DIR 则尊重现值）
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app}"

PROJECT="CopyPasty"
SCHEME="CopyPasty"
DERIVED="build/DerivedData"
TEAM="6XVGB2XZ5Y"

# 从工程配置读取版本号
MARKETING_VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$PROJECT.xcodeproj/project.pbxproj" | head -1)
CURRENT_PROJECT_VERSION=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);.*/\1/p' "$PROJECT.xcodeproj/project.pbxproj" | head -1)
echo "== 版本: $MARKETING_VERSION ($CURRENT_PROJECT_VERSION) =="

# Release 构建（用本机钥匙串的开发者身份签名，本机可直接运行）
xcodebuild -project "$PROJECT.xcodeproj" -scheme "$SCHEME" \
    -configuration Release -derivedDataPath "$DERIVED" \
    -destination 'platform=macOS' \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic build \
    2>&1 | { grep -E 'error:|BUILD' || true; }

APP="$DERIVED/Build/Products/Release/CopyPasty.app"
[ -d "$APP" ] || { echo "错误: 未找到构建产物 $APP"; exit 1; }

codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Authority' | head -2 || true

# 组装 DMG 暂存目录：App + 指向 Applications 的软链接（拖拽安装）
STAGING="build/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# 生成压缩 DMG
OUT="build/CopyPasty-$MARKETING_VERSION.dmg"
rm -f "$OUT"
hdiutil create -volname "CopyPasty $MARKETING_VERSION" \
    -srcfolder "$STAGING" -ov -format UDZO "$OUT" > /dev/null

rm -rf "$STAGING"
echo "== 完成: $OUT =="
ls -lh "$OUT"
echo "提示: 发给别人时，对方首次打开需右键 -> 打开（或在系统设置 -> 隐私与安全性里点『仍要打开』）；自己机器上直接运行。"
