#!/bin/bash
# Builds build/VibeKeys.app (universal: Apple Silicon + Intel) with the Swift compiler from the
# Xcode Command Line Tools (xcode-select --install). No Xcode project needed.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/VibeKeys.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13.0" -o "build/VibeKeys-$arch" Sources/*.swift
done
lipo -create -output "$APP/Contents/MacOS/VibeKeys" build/VibeKeys-arm64 build/VibeKeys-x86_64
rm build/VibeKeys-arm64 build/VibeKeys-x86_64
cp Info.plist "$APP/Contents/Info.plist"

# App icon from the 1024 px master
ICONSET=build/AppIcon.iconset
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Ad-hoc signature so the app runs locally (macOS asks again for Accessibility after each rebuild)
codesign --force --sign - "$APP"
echo "Built $APP"
