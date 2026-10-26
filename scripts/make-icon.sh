#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from the SwiftUI AppIcon view.
set -euo pipefail
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

swift build
.build/debug/Spectrum preview "$work" >/dev/null
iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$work/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$work/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
mkdir -p Resources
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
echo "Resources/AppIcon.icns"
