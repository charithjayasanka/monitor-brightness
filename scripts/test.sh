#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
clang -Wall -Wextra -Werror Tests/DDCTests.c Sources/DDC.c -framework CoreGraphics -framework IOKit -framework CoreFoundation -o build/DDCTests
build/DDCTests
mkdir -p build/module-cache
swiftc -module-cache-path build/module-cache Sources/ScreenTarget.swift Tests/ScreenTargetTests.swift -framework AppKit -o build/ScreenTargetTests
build/ScreenTargetTests
