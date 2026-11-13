#!/usr/bin/env bash
# Renders the app icon from the project artwork (ADR-0033): 1024 × 1024 without alpha, as App Store Connect requires;
# and from the same artwork the faint radio of the launch screen, light and dark, at three scales (ADR-0073).
# Usage: app-icon.sh (run by `make icon`; commit the result)
set -euo pipefail

cd "$(dirname "$0")/.."
source=../artwork/app-icon.svg
target=App/KV4PHT/Assets.xcassets/AppIcon.appiconset/AppIcon.png
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

sips -s format png -z 1024 1024 "$source" --out "$work/icon.png" >/dev/null
# The artwork fills the square; a round trip through JPEG at the highest quality drops the unused alpha channel.
sips -s format jpeg -s formatOptions 100 "$work/icon.png" --out "$work/icon.jpg" >/dev/null
sips -s format png "$work/icon.jpg" --out "$target" >/dev/null
echo "app-icon: $target"

# The radio without the background of the icon and without its lettering, faint. One image for light and dark: the
# launch screen takes no image for each appearance, so a grey between the two colours of the icon shows on both.
launch=App/KV4PHT/Assets.xcassets/LaunchLogo.imageset
sed -e 's|<rect width="512" height="512" fill="#FFFCEA"/>||' \
  -e 's|fill="#FFFCEA"|fill="none"|g' \
  -e 's|fill="#21201F"|fill="#8C8A80" fill-opacity="0.25"|g' "$source" > "$work/launch.svg"
for scale in 1 2 3; do
  suffix=$([ "$scale" = 1 ] && echo "" || echo "@${scale}x")
  sips -s format png -z $((210 * scale)) $((210 * scale)) "$work/launch.svg" --out "$launch/LaunchLogo$suffix.png" >/dev/null
done
echo "app-icon: $launch"
