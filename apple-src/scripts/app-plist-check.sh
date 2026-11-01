#!/usr/bin/env bash
# Fails unless the built iOS app meets what it needs at run time and in App Store Connect:
# - background modes audio and bluetooth-central (ADR-0031);
# - an app icon, a privacy manifest and the export compliance answer (ADR-0033).
# Usage: app-plist-check.sh <path to KV4PHT.app>
set -euo pipefail

app="$1"
plist="$app/Info.plist"
fail() {
  echo "app-plist: $1" >&2
  exit 1
}

modes=$(plutil -extract UIBackgroundModes json -o - "$plist" 2>/dev/null || echo '[]')
for mode in audio bluetooth-central; do
  jq -e --arg mode "$mode" 'index($mode) != null' <<<"$modes" >/dev/null || fail "UIBackgroundModes in $plist lacks $mode"
done
[[ "$(plutil -extract CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName raw -o - "$plist" 2>/dev/null)" == AppIcon ]] || fail "$plist has no app icon"
[[ -f "$app/Assets.car" ]] || fail "$app has no compiled asset catalog"
[[ "$(plutil -extract ITSAppUsesNonExemptEncryption raw -o - "$plist" 2>/dev/null)" == false ]] ||
  fail "$plist does not declare ITSAppUsesNonExemptEncryption = NO"
[[ -f "$app/PrivacyInfo.xcprivacy" ]] || fail "$app has no privacy manifest"
plutil -lint -s "$app/PrivacyInfo.xcprivacy" || fail "the privacy manifest is not a valid property list"
echo "app-plist: ok"
