#!/usr/bin/env bash
# Builds the macOS release (ADR-0034): archive, Developer ID signature with hardened runtime, DMG, notarization and
# stapling. The signing data comes from the environment only and never enters the repository:
#   TEAM_ID         Apple Developer team ID (required unless SIGN_IDENTITY is "-")
#   NOTARY_PROFILE  keychain profile of `xcrun notarytool store-credentials`; without it, notarization is skipped
#   SIGN_IDENTITY   default "Developer ID Application"; "-" signs ad hoc for a local dry run
# Usage: release-macos.sh (run by `make release`)
set -euo pipefail

cd "$(dirname "$0")/.."
identity="${SIGN_IDENTITY:-Developer ID Application}"
team="${TEAM_ID:-}"
if [[ "$identity" != "-" && -z "$team" ]]; then
  echo "release: set TEAM_ID (or SIGN_IDENTITY=- for an unsigned dry run)" >&2
  exit 1
fi

out=.build/release
rm -rf "$out"
mkdir -p "$out"
archive="$out/KV4PHT.xcarchive"

xcodebuild archive -quiet -project App/KV4PHT.xcodeproj -scheme KV4PHT -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$archive" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" ENABLE_HARDENED_RUNTIME=YES

app="$archive/Products/Applications/KV4PHT.app"
version=$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")
build=$(plutil -extract CFBundleVersion raw -o - "$app/Contents/Info.plist")
codesign --verify --deep --strict "$app"
signature=$(codesign --display --verbose=2 "$app" 2>&1)
[[ "$signature" == *"flags="*runtime* ]] || {
  echo "release: $app lacks the hardened runtime" >&2
  exit 1
}

dmg="$out/kv4p-HT-$version-$build.dmg"
stage="$out/dmg"
mkdir -p "$stage"
ditto "$app" "$stage/kv4p HT.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "kv4p HT $version" -srcfolder "$stage" -format UDZO "$dmg"

if [[ "$identity" == "-" ]]; then
  echo "release: dry run, signed ad hoc and not notarized: $dmg"
  exit 0
fi
codesign --sign "$identity" --timestamp "$dmg"
if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo "release: signed, not notarized (set NOTARY_PROFILE): $dmg"
  exit 0
fi
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"
echo "release: signed, notarized and stapled: $dmg"
