#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 L99 for Mac contributors

set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${L99_BUILD_ROOT:-"$PROJECT_DIR/.build"}"
mkdir -p "$BUILD_ROOT/swift-cache"
SOURCES=()
for source in "$PROJECT_DIR"/macos/*.swift; do
    case "$source" in */App.swift|*/Views.swift) ;; *) SOURCES+=("$source");; esac
done
swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macos14.0 \
    -module-cache-path "$BUILD_ROOT/swift-cache" \
    -import-objc-header "$PROJECT_DIR/macos/L99Core.h" \
    "${SOURCES[@]}" "$PROJECT_DIR/tests/ConfigurationTests.swift" "$PROJECT_DIR/tests/ConnectionTests.swift" "$PROJECT_DIR/tests/LocalizationTests.swift" \
    "$BUILD_ROOT/rust/release/libaula_l99_core.a" \
    -framework SwiftUI -framework AppKit -framework IOKit -framework CoreFoundation \
    -framework CoreAudio -framework AudioToolbox -framework Accelerate \
    -o "$BUILD_ROOT/configuration-tests"
"$BUILD_ROOT/configuration-tests" "$PROJECT_DIR"
