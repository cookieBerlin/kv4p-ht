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

# A simulator this script booted is shut down again once its device is done, so that only one runs at a time.
booted=""
shutdown_simulator() {
  if [ -n "$booted" ]; then
    xcrun simctl shutdown "$booted" > /dev/null 2>&1 || true
    booted=""
  fi
}
trap shutdown_simulator EXIT

# The UDID of the simulator of this name with the newest iOS, the one a destination by name would take; empty if none.
simulator() {
  xcrun simctl list devices available -j | jq -r --arg name "$1" '
    [.devices | to_entries[] | select(.key | test("SimRuntime\\.iOS-"))
      | (.key | capture("iOS-(?<major>[0-9]+)-(?<minor>[0-9]+)") | [(.major | tonumber), (.minor | tonumber)]) as $version
      | .value[] | select(.name == $name) | {udid, $version}]
    | sort_by(.version) | last | .udid // empty'
}

# The tests of a result bundle that failed, as -only-testing arguments, one per line; "all" when a failure names no
# test, such as a test runner that crashed between two tests.
failed_tests() {
  xcrun xcresulttool get test-results summary --path "$1" | jq -r '
    [.testFailures[]? | if (.testIdentifierString | test("/")) then
      "-only-testing:\(.targetName)/\(.testIdentifierString | sub("\\(\\)$"; ""))" else "all" end]
    | if index("all") then "all" else unique[] end'
}

# One run of the given tests into a result bundle of its own, which must not exist yet. A test runner that crashes
# before the tests start, as it does at times on a busy machine, gets a second start; the log of the first stays.
run_tests() {
  local bundle="$1" log="$2" attempt
  shift 2
  for attempt in 1 2; do
    rm -rf "$bundle"
    if xcodebuild test -project "$project" -scheme KV4PHT "${target[@]}" "$@" \
      -resultBundlePath "$bundle" > "$log" 2>&1; then
      return 0
    fi
    if [ "$attempt" = 1 ] && grep -qE "never finished bootstrapping|failed to initialize for UI testing|crashed while preparing to run tests|timed out while preparing to run tests" "$log"; then
      echo "a11y: the test runner did not start on $device, once more" >&2
      mv "$log" "${log%.log} not started.log"
      continue
    fi
    return 1
  done
}

run=$(date +%Y%m%d-%H%M%S)
for device in "${devices[@]}"; do
  log="$results/$device.log"
  retry_log="$results/$device retry.log"
  rm -f "$retry_log" "$results/$device not started.log" "$results/$device retry not started.log"
  bundle="$results/runs/$run/$device.xcresult"
  retry_bundle="$results/runs/$run/$device retry.xcresult"
  mkdir -p "$results/runs/$run"
  started=$SECONDS
  # The Mac runs the tests itself, and its test runner must be signed: ad hoc, without a team. It is built outside the
  # checkout, as macOS asks each new build for access to a protected folder such as Documents, where the checkout may be.
  if [ "$device" = Mac ]; then
    target=(-destination "platform=macOS" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
      -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/KV4PHT-a11y-mac")
  else
    udid="$(simulator "$device")"
    if [ -z "$udid" ]; then
      echo "a11y: no simulator named $device" >&2
      status=1
      continue
    fi
    target=(-destination "platform=iOS Simulator,id=$udid" CODE_SIGNING_ALLOWED=NO -derivedDataPath "$results/derived")
    xcrun simctl list devices booted | grep -q "$udid" || booted="$udid"
  fi
  # A test that fails runs once more, in a new test runner, and only that test: once the run of the whole selection is
  # over, its result bundle names the tests that failed.
  if ! run_tests "$bundle" "$log" "${tests[@]}"; then
    retry=()
    while IFS= read -r test; do
      [ "$test" = all ] && retry=("${tests[@]}") && break
      retry+=("$test")
    done < <(failed_tests "$bundle" 2> /dev/null || echo all)
    [ "${#retry[@]}" -gt 0 ] || retry=("${tests[@]}")
    echo "a11y: once more on $device: ${retry[*]#-only-testing:}" >&2
    if ! run_tests "$retry_bundle" "$retry_log" "${retry[@]}"; then
      echo "a11y: the UI tests failed on $device, see $retry_log" >&2
      status=1
    fi
  fi
  echo "a11y: $device took $((SECONDS - started)) s"
  # The screenshots of each screen, to judge the findings.
  for each in "$bundle" "$retry_bundle"; do
    [ -d "$each" ] || continue
    xcrun xcresulttool export attachments --path "$each" \
      --output-path "${each%.xcresult} screenshots" > /dev/null 2>&1 || true
  done
  shutdown_simulator
done
echo "a11y: screenshots in $results/runs/$run"

# Each finding with the device it was found on, from the run and from the run once more.
for device in "${devices[@]}"; do
  for each in "$results/$device.log" "$results/$device retry.log"; do
    [ -f "$each" ] || continue
    grep -h '^A11Y' "$each" | sed "s/^A11Y /A11Y $device, /" || true
  done
done | sort -u > "$results/findings.txt"
# The findings only, not the exceptions the test let pass, which the file lists as well.
echo "a11y: $(grep '^A11Y ' "$results/findings.txt" | grep -vc 'no findings' || true) findings in $results/findings.txt"
exit "$status"
