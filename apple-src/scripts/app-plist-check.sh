#!/usr/bin/env bash
# Fails unless the built iOS app declares the background modes it needs (ADR-0031):
# audio keeps RX playing with the screen locked, bluetooth-central keeps the radio connected.
# Usage: app-plist-check.sh <path to KV4PHT.app>
set -euo pipefail

plist="$1/Info.plist"
modes=$(plutil -extract UIBackgroundModes json -o - "$plist" 2>/dev/null || echo '[]')
for mode in audio bluetooth-central; do
  if ! jq -e --arg mode "$mode" 'index($mode) != null' <<<"$modes" >/dev/null; then
    echo "app-plist: UIBackgroundModes in $plist lacks $mode" >&2
    exit 1
  fi
done
echo "app-plist: ok"
