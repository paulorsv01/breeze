#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/AppIcon.iconset
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" Resources/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
sips -z 256 256 Resources/AppIcon.png --out Resources/IconPreview.png >/dev/null
