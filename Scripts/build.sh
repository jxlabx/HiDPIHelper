#!/bin/zsh
set -eu
PROJECT_ROOT="${0:A:h:h}"
BUILD_DIR="$PROJECT_ROOT/.build"
APP_DIR="$PROJECT_ROOT/dist/HiDPI Helper.app"
BUILD_ARCH=${BUILD_ARCH:-$(uname -m)}
[[ "$BUILD_ARCH" == arm64 || "$BUILD_ARCH" == x86_64 ]] || { echo "不支持的构建架构：$BUILD_ARCH"; exit 1; }
mkdir -p "$BUILD_DIR/app" "$BUILD_DIR/config" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
CORE=("$PROJECT_ROOT"/Sources/Core/*.swift)
# 合并纯配置逻辑，供应用与管理员安装器共同编译。
cat "${CORE[@]}" "$PROJECT_ROOT/Sources/App/main.swift" > "$BUILD_DIR/app/main.swift"
cat "$PROJECT_ROOT/Sources/Core/DisplayProfile.swift" "$PROJECT_ROOT/Sources/Core/DisplayConfiguration.swift" "$PROJECT_ROOT/Sources/ConfigTool/main.swift" > "$BUILD_DIR/config/main.swift"
xcrun swiftc -O -target "${BUILD_ARCH}-apple-macosx13.0" -module-cache-path "$BUILD_DIR/cache" "$BUILD_DIR/app/main.swift" -o "$APP_DIR/Contents/MacOS/HiDPIHelper"
xcrun swiftc -O -target "${BUILD_ARCH}-apple-macosx13.0" -module-cache-path "$BUILD_DIR/cache" "$BUILD_DIR/config/main.swift" -o "$APP_DIR/Contents/MacOS/ConfigTool"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP_DIR/Contents/MacOS/ConfigTool"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "已构建：$APP_DIR"
