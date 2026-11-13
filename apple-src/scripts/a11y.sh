#!/usr/bin/env bash
# Runs the UI tests on each simulator, or on this Mac, and collects the findings of the accessibility audit (ADR-0062).
# Usage: scripts/a11y.sh <project> "<device>,<device>" [all|audit|functional], where the device "Mac" stands for this
# Mac; `audit` runs only the accessibility audit, `functional` all other UI tests (ADR-0072).
set -euo pipefail

project="$1"
IFS=',' read -r -a devices <<< "$2"
case "${3:-all}" in
  all) tests=(-only-testing:KV4PHTUITests) ;;
  audit) tests=(-only-testing:KV4PHTUITests/AccessibilityAuditTests) ;;
  functional) tests=(-only-testing:KV4PHTUITests -skip-testing:KV4PHTUITests/AccessibilityAuditTests) ;;
  *) echo "a11y: unknown selection $3, use all, audit or functional" >&2; exit 2 ;;
esac
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
  # A test that fails is run once more, in a new test runner. A test runner that crashes before the tests start, as it
  # does at times on a busy machine, gets a second start of its own; its result bundle is replaced.
  for attempt in 1 2; do
    rm -rf "$bundle"
    if xcodebuild test -project "$project" -scheme KV4PHT "${target[@]}" "${tests[@]}" \
      -retry-tests-on-failure -test-iterations 2 -test-repetition-relaunch-enabled YES \
      -resultBundlePath "$bundle" > "$log" 2>&1; then
      break
    fi
    if [ "$attempt" = 1 ] && grep -qE "never finished bootstrapping|failed to initialize for UI testing|crashed while preparing to run tests" "$log"; then
      echo "a11y: the test runner did not start on $device, once more" >&2
      continue
    fi
    echo "a11y: the UI tests failed on $device, see $log" >&2
    status=1
    break
  done
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
