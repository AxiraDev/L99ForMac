#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 L99 for Mac contributors

set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SESSION_DIR="$(cd "$PROJECT_DIR/../.." && pwd)"
if command -v cargo >/dev/null 2>&1; then
    CARGO_BIN="$(command -v cargo)"
elif [ -x "$SESSION_DIR/work/tools/cargo/bin/cargo" ]; then
    export CARGO_HOME="$SESSION_DIR/work/tools/cargo"
    export RUSTUP_HOME="$SESSION_DIR/work/tools/rustup"
    CARGO_BIN="$CARGO_HOME/bin/cargo"
else
    echo 'Rust is required: https://rust-lang.org/install/' >&2
    exit 1
fi
BUILD_ROOT="${L99_BUILD_ROOT:-"$PROJECT_DIR/.build"}"
export CARGO_TARGET_DIR="$BUILD_ROOT/rust"
mkdir -p "$BUILD_ROOT/swift-cache"
"$CARGO_BIN" test --manifest-path "$PROJECT_DIR/core/Cargo.toml" --quiet
"$CARGO_BIN" build --manifest-path "$PROJECT_DIR/core/Cargo.toml" --release --quiet
STAGING_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/l99-build.XXXXXX")"
APP_DIR="$STAGING_DIR/L99 for Mac.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp -R "$PROJECT_DIR/resources" "$APP_DIR/Contents/Resources/"
cp "$PROJECT_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
cp "$PROJECT_DIR/resources/Credits.rtf" "$APP_DIR/Contents/Resources/Credits.rtf"
cp -R "$PROJECT_DIR/macos/Localizations/"*.lproj "$APP_DIR/Contents/Resources/"
cp "$PROJECT_DIR/resources/branding/Shark.icns" "$APP_DIR/Contents/Resources/Shark.icns"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>L99forMac</string>
<key>CFBundleIdentifier</key><string>local.aula.l99.preview</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>ru</string><string>en</string><string>zh-Hans</string></array>
<key>CFBundleName</key><string>L99 for Mac</string>
<key>CFBundleIconFile</key><string>Shark</string>
<key>CFBundleShortVersionString</key><string>0.10.1</string>
<key>CFBundleVersion</key><string>14</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 L99 for Mac contributors. GNU GPLv3 (GPL-3.0-only). No warranty.</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAudioCaptureUsageDescription</key><string>System audio drives the live spectrum on the L99 display and lighting. Audio is processed locally and never saved.</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macos14.0 \
    -module-cache-path "$BUILD_ROOT/swift-cache" \
    -import-objc-header "$PROJECT_DIR/macos/L99Core.h" \
    "$PROJECT_DIR/macos/Localization.swift" "$PROJECT_DIR/macos/Support.swift" "$PROJECT_DIR/macos/Hardware.swift" "$PROJECT_DIR/macos/SystemMetrics.swift" "$PROJECT_DIR/macos/MusicAudio.swift" "$PROJECT_DIR/macos/MusicHardware.swift" "$PROJECT_DIR/macos/Screen.swift" "$PROJECT_DIR/macos/DisplayTransport.swift" "$PROJECT_DIR/macos/Recording.swift" "$PROJECT_DIR/macos/Models.swift" \
    "$PROJECT_DIR/macos/InputCheck.swift" "$PROJECT_DIR/macos/Connection.swift" "$PROJECT_DIR/macos/DeviceConfiguration.swift" "$PROJECT_DIR/macos/SessionStore.swift" \
    "$PROJECT_DIR/macos/Views.swift" "$PROJECT_DIR/macos/App.swift" \
    "$CARGO_TARGET_DIR/release/libaula_l99_core.a" \
    -framework SwiftUI -framework AppKit -framework IOKit -framework CoreFoundation -framework CoreAudio -framework AudioToolbox -framework Accelerate \
    -o "$APP_DIR/Contents/MacOS/L99forMac"
xattr -cr "$APP_DIR"
codesign --force --deep --options runtime --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
FINAL_APP_DIR="$PROJECT_DIR/L99 for Mac.app"
mkdir -p "$FINAL_APP_DIR/Contents/MacOS"
# Replace the executable by rename so macOS never sees an in-place modification
# of a signed executable that may still be running.
cp -X "$APP_DIR/Contents/MacOS/L99forMac" "$FINAL_APP_DIR/Contents/MacOS/L99forMac.next"
mv -f "$FINAL_APP_DIR/Contents/MacOS/L99forMac.next" "$FINAL_APP_DIR/Contents/MacOS/L99forMac"
cp -RX "$APP_DIR/Contents/Resources" "$FINAL_APP_DIR/Contents/"
cp -RX "$APP_DIR/Contents/_CodeSignature" "$FINAL_APP_DIR/Contents/"
cp -X "$APP_DIR/Contents/Info.plist" "$FINAL_APP_DIR/Contents/Info.plist"
printf 'Built: %s\n' "$FINAL_APP_DIR"
