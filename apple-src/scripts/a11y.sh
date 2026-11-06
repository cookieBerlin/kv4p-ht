#!/usr/bin/env bash
# Runs the accessibility audit of the UI tests on each simulator and collects the findings (ADR-0062).
# Usage: scripts/a11y.sh <project> "<device>,<device>"
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
  if ! xcodebuild test -project "$project" -scheme KV4PHT \
    -destination "platform=iOS Simulator,name=$device" \
    -only-testing:KV4PHTUITests CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath "$results/derived" -resultBundlePath "$bundle" > "$log" 2>&1; then
    echo "a11y: the UI tests failed on $device, see $log" >&2
    status=1
  fi
  # The screenshots of each screen, to judge the findings.
  xcrun xcresulttool export attachments --path "$bundle" \
    --output-path "$results/runs/$run/$device screenshots" > /dev/null 2>&1 || true
done
echo "a11y: screenshots in $results/runs/$run"

grep -h '^A11Y' "$results"/*.log | sort -u > "$results/findings.txt" || true
echo "a11y: $(grep -vc 'no findings' "$results/findings.txt" || true) findings in $results/findings.txt"
exit "$status"
