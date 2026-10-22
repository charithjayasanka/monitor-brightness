#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/MonitorBrightness.app/Contents/MacOS build/module-cache
clang -arch arm64 -mmacosx-version-min=13.0 -Wall -Wextra -Werror -O2 -c Sources/DDC.c -o build/DDC.o
swiftc -target arm64-apple-macosx13.0 -swift-version 5 -O -module-cache-path build/module-cache -import-objc-header Sources/DDC.h Sources/ScreenTarget.swift Sources/KeyRouting.swift Sources/BrightnessKeys.swift Sources/App.swift build/DDC.o -framework AppKit -framework CoreGraphics -framework IOKit -framework ServiceManagement -o build/MonitorBrightness.app/Contents/MacOS/MonitorBrightness
cp Sources/Info.plist build/MonitorBrightness.app/Contents/Info.plist
codesign --force --sign - build/MonitorBrightness.app
echo "Built: $PWD/build/MonitorBrightness.app"
