#!/bin/zsh
set -eu
PROJECT_ROOT="${0:A:h:h}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/Resources/Info.plist")
BUILD_ARCH=${BUILD_ARCH:-$(uname -m)}
export BUILD_ARCH
"$PROJECT_ROOT/Scripts/build.sh"
ditto -c -k --norsrc --noextattr --keepParent "$PROJECT_ROOT/dist/HiDPI Helper.app" "$PROJECT_ROOT/dist/HiDPIHelper-$VERSION-$BUILD_ARCH.zip"
echo "已打包：HiDPIHelper-$VERSION-$BUILD_ARCH.zip"
