#!/usr/bin/env bash
# Renders the app icon from the project artwork (ADR-0033): 1024 × 1024 without alpha, as App Store Connect requires.
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
