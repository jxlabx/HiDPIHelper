#!/bin/zsh
set -eu
PROJECT_ROOT="${0:A:h:h}"
BUILD_DIR="$PROJECT_ROOT/.build/icon"
mkdir -p "$BUILD_DIR"
xcrun swiftc -module-cache-path "$PROJECT_ROOT/.build/cache" "$PROJECT_ROOT/Assets/GenerateIcon.swift" -o "$BUILD_DIR/generate-icon"
"$BUILD_DIR/generate-icon" "$BUILD_DIR/AppIcon.iconset"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$PROJECT_ROOT/Resources/AppIcon.icns"
cp "$BUILD_DIR/AppIcon.iconset/icon_512x512@2x.png" "$PROJECT_ROOT/Assets/AppIcon.png"
echo '图标已生成。'
