#!/bin/zsh
set -eu
PROJECT_ROOT="${0:A:h:h}"
BUILD_DIR="$PROJECT_ROOT/.build/tests"
mkdir -p "$BUILD_DIR"
cat "$PROJECT_ROOT/Sources/Core/DisplayProfile.swift" "$PROJECT_ROOT/Sources/Core/DisplayConfiguration.swift" "$PROJECT_ROOT/Tests/main.swift" > "$BUILD_DIR/main.swift"
xcrun swiftc -module-cache-path "$PROJECT_ROOT/.build/cache" "$BUILD_DIR/main.swift" -o "$BUILD_DIR/tests"
# 分别在中英文环境运行，避免测试依赖本地化文案。
for language in en zh-Hans; do
  TEST_ROOT=$(mktemp -d "$BUILD_DIR/run.$language.XXXXXX")
  echo "测试语言：$language"
  "$BUILD_DIR/tests" "$TEST_ROOT" -AppleLanguages "($language)"
done
