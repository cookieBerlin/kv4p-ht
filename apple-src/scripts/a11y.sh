#!/usr/bin/env bash
# Runs the accessibility audit of the UI tests on each simulator, or on this Mac, and collects the findings (ADR-0062).
# Usage: scripts/a11y.sh <project> "<device>,<device>", where the device "Mac" stands for this Mac
set -euo pipefail

project="$1"
IFS=',' read -r -a devices <<< "$2"
results=.build/a11y
mkdir -p "$results"
status=0

run=$(date +%Y%m%d-%H%M%S)
for device in "${devices[@]}"; do
  log="$results/$device.log"
  # A result bundle must not exist yet, so each run has its own.
  bundle="$results/runs/$run/$device.xcresult"
  mkdir -p "$results/runs/$run"
  # The Mac runs the tests itself, and its test runner must be signed: ad hoc, without a team. It is built outside the
  # checkout, as macOS asks each new build for access to a protected folder such as Documents, where the checkout may be.
  if [ "$device" = Mac ]; then
    target=(-destination "platform=macOS" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
      -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/KV4PHT-a11y-mac")
  else
    target=(-destination "platform=iOS Simulator,name=$device" CODE_SIGNING_ALLOWED=NO -derivedDataPath "$results/derived")
  fi
  if ! xcodebuild test -project "$project" -scheme KV4PHT "${target[@]}" -only-testing:KV4PHTUITests \
    -resultBundlePath "$bundle" > "$log" 2>&1; then
    echo "a11y: the UI tests failed on $device, see $log" >&2
    status=1
  fi
  # The screenshots of each screen, to judge the findings.
  xcrun xcresulttool export attachments --path "$bundle" \
    --output-path "$results/runs/$run/$device screenshots" > /dev/null 2>&1 || true
done
echo "a11y: screenshots in $results/runs/$run"

# Each finding with the device it was found on.
for device in "${devices[@]}"; do
  grep -h '^A11Y' "$results/$device.log" | sed "s/^A11Y /A11Y $device, /" || true
done | sort -u > "$results/findings.txt"
# The findings only, not the exceptions the test let pass, which the file lists as well.
echo "a11y: $(grep '^A11Y ' "$results/findings.txt" | grep -vc 'no findings' || true) findings in $results/findings.txt"
exit "$status"
