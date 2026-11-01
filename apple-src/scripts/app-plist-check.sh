#!/usr/bin/env bash
# Fails unless the built app meets what it needs at run time and in App Store Connect:
# - iOS: background modes audio and bluetooth-central (ADR-0031);
# - an app icon, a privacy manifest and the export compliance answer (ADR-0033);
# - no nested resource bundles, because the App Store export does not sign them again (ADR-0033).
# Usage: app-plist-check.sh <path to KV4PHT.app>
set -euo pipefail

app="$1"
fail() {
  echo "app-plist: $1" >&2
  exit 1
}

if [[ -d "$app/Contents" ]]; then
  plist="$app/Contents/Info.plist"
  resources="$app/Contents/Resources"
  icon_key=CFBundleIconName
else
  plist="$app/Info.plist"
  resources="$app"
  icon_key=CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName
  modes=$(plutil -extract UIBackgroundModes json -o - "$plist" 2>/dev/null || echo '[]')
  for mode in audio bluetooth-central; do
    jq -e --arg mode "$mode" 'index($mode) != null' <<<"$modes" >/dev/null || fail "UIBackgroundModes in $plist lacks $mode"
  done
fi
[[ "$(plutil -extract "$icon_key" raw -o - "$plist" 2>/dev/null)" == AppIcon ]] || fail "$plist has no app icon"
[[ -f "$resources/Assets.car" ]] || fail "$app has no compiled asset catalog"
[[ "$(plutil -extract ITSAppUsesNonExemptEncryption raw -o - "$plist" 2>/dev/null)" == false ]] ||
  fail "$plist does not declare ITSAppUsesNonExemptEncryption = NO"
[[ -f "$resources/PrivacyInfo.xcprivacy" ]] || fail "$app has no privacy manifest"
plutil -lint -s "$resources/PrivacyInfo.xcprivacy" || fail "the privacy manifest is not a valid property list"
nested=$(find "$resources" -name '*.bundle')
[[ -z "$nested" ]] || fail "$app has nested bundles: $nested"
echo "app-plist: ok"
