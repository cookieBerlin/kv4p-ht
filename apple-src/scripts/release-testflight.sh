#!/usr/bin/env bash
# Builds the iOS and macOS apps for TestFlight (ADR-0035): archive, App Store signing and upload to App Store Connect.
# The signing data comes from the environment and the Xcode account only and never enters the repository:
#   TEAM_ID       Apple Developer team ID (required unless DRY_RUN is set)
#   PLATFORMS     default "iOS macOS"; for example "macOS" uploads the Mac app only
#   BUILD_NUMBER  default: the UTC time, as App Store Connect wants a new number for every upload
#   DRY_RUN       set to 1 to archive without signing and check the bundles, without uploading
# Usage: release-testflight.sh (run by `make testflight`)
set -euo pipefail

cd "$(dirname "$0")/.."
team="${TEAM_ID:-}"
dry_run="${DRY_RUN:-}"
if [[ -z "$dry_run" && -z "$team" ]]; then
  echo "testflight: set TEAM_ID (or DRY_RUN=1 for an unsigned dry run)" >&2
  exit 1
fi

out=.build/testflight
rm -rf "$out"
mkdir -p "$out"
build="${BUILD_NUMBER:-$(date -u +%Y%m%d.%H%M)}"
commit=$(git rev-parse --short=7 HEAD)
[[ -z "$(git status --porcelain)" ]] || commit="$commit-dirty"

# Generated here, because the team ID must not be committed.
options="$out/ExportOptions.plist"
if [[ -z "$dry_run" ]]; then
  plutil -create xml1 "$options"
  plutil -insert method -string app-store-connect "$options"
  plutil -insert destination -string upload "$options"
  plutil -insert signingStyle -string automatic "$options"
  plutil -insert teamID -string "$team" "$options"
  plutil -insert manageAppVersionAndBuildNumber -bool false "$options"
fi

for platform in ${PLATFORMS:-iOS macOS}; do
  scripts/what-to-test.sh "$platform" >"$out/WhatToTest-$platform.txt"
  archive="$out/KV4PHT-$platform.xcarchive"
  archive_command=(xcodebuild archive -quiet -project App/KV4PHT.xcodeproj -scheme KV4PHT -configuration Release
    -destination "generic/platform=$platform" -archivePath "$archive" CURRENT_PROJECT_VERSION="$build" KV4P_COMMIT="$commit")
  if [[ -n "$dry_run" ]]; then
    "${archive_command[@]}" CODE_SIGNING_ALLOWED=NO
    scripts/app-plist-check.sh "$archive/Products/Applications/KV4PHT.app" "$commit"
    echo "testflight: dry run, unsigned and not uploaded: $archive"
    continue
  fi
  # The command line overrides the ad hoc identity Base.xcconfig sets for local Mac builds.
  "${archive_command[@]}" -allowProvisioningUpdates DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic \
    CODE_SIGN_IDENTITY="Apple Development"
  scripts/app-plist-check.sh "$archive/Products/Applications/KV4PHT.app" "$commit"
  xcodebuild -exportArchive -quiet -archivePath "$archive" -exportOptionsPlist "$options" \
    -exportPath "$out/export-$platform" -allowProvisioningUpdates
  echo "testflight: uploaded the $platform build $build to App Store Connect"
  echo "testflight: paste $out/WhatToTest-$platform.txt into What to Test of that build"
done
