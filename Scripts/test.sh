#!/bin/zsh
set -eu
PROJECT_ROOT="${0:A:h:h}"
BUILD_DIR="$PROJECT_ROOT/.build/tests"
mkdir -p "$BUILD_DIR"
cat "$PROJECT_ROOT/Sources/Core/DisplayProfile.swift" "$PROJECT_ROOT/Sources/Core/DisplayConfiguration.swift" "$PROJECT_ROOT/Tests/main.swift" > "$BUILD_DIR/main.swift"
xcrun swiftc -module-cache-path "$PROJECT_ROOT/.build/cache" "$BUILD_DIR/main.swift" -o "$BUILD_DIR/tests"
TEST_ROOT=$(mktemp -d "$BUILD_DIR/run.XXXXXX")
"$BUILD_DIR/tests" "$TEST_ROOT"
