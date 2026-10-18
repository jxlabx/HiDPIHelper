#!/bin/zsh
set -eu
PROJECT_ROOT="${0:A:h:h}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/Resources/Info.plist")
ARCH=$(uname -m)
"$PROJECT_ROOT/Scripts/build.sh"
ditto -c -k --sequesterRsrc --keepParent "$PROJECT_ROOT/dist/HiDPI Helper.app" "$PROJECT_ROOT/dist/HiDPIHelper-$VERSION-$ARCH.zip"
echo "已打包：HiDPIHelper-$VERSION-$ARCH.zip"
