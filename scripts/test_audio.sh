#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 L99 for Mac contributors

set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/l99-audio-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 5 -O -parse-as-library \
    -module-cache-path "$TEST_DIR/cache" \
    "$PROJECT_DIR/macos/Localization.swift" "$PROJECT_DIR/macos/MusicAudio.swift" "$PROJECT_DIR/tests/MusicDSPTests.swift" \
    -o "$TEST_DIR/music-dsp-tests" -framework CoreAudio -framework AudioToolbox -framework Accelerate -framework SwiftUI -framework AppKit
"$TEST_DIR/music-dsp-tests"
