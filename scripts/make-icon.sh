#!/bin/bash
# Regenerates the app icon and README logo from assets/vocume.svg (the single source of the logo).
#   scripts/make-icon.sh
set -euo pipefail
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
iconset="$work/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
  swift scripts/render-icon.swift assets/vocume.svg "$iconset/icon_${size}x${size}.png" "$size" --mac-icon
  swift scripts/render-icon.swift assets/vocume.svg "$iconset/icon_${size}x${size}@2x.png" "$((size * 2))" --mac-icon
done
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
swift scripts/render-icon.swift assets/vocume.svg assets/vocume-256.png 256
echo "Wrote Resources/AppIcon.icns and assets/vocume-256.png"
