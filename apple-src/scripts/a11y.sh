#!/usr/bin/env bash
# Runs the UI tests on each simulator, or on this Mac, and collects the findings of the accessibility audit (ADR-0062).
# Usage: scripts/a11y.sh <project> "<device>,<device>" [all|audit|audit-pages|audit-settings|functional], where the
# device "Mac" stands for this Mac; `audit` runs only the accessibility audit, `audit-pages` and `audit-settings` one of
# its two parts, and `functional` all other UI tests (ADR-0072). With A11Y_LOAD_LOG=1, it logs how busy the machine is.
set -euo pipefail

project="$1"
IFS=',' read -r -a devices <<< "$2"
audit=KV4PHTUITests/AccessibilityAuditTests
# The first start of the app, which runs before every selection and in none of them.
warm_up=KV4PHTUITests/WarmUpTests
case "${3:-all}" in
  all) tests=(-only-testing:KV4PHTUITests -skip-testing:"$warm_up") ;;
  audit) tests=(-only-testing:"$audit") ;;
  audit-pages) tests=(-only-testing:"$audit/testPagesWithDefaultText" -only-testing:"$audit/testPagesWithLargestText") ;;
  audit-settings)
    tests=(-only-testing:"$audit/testSettingsWithDefaultText" -only-testing:"$audit/testSettingsWithLargestText") ;;
  functional) tests=(-only-testing:KV4PHTUITests -skip-testing:"$audit" -skip-testing:"$warm_up") ;;
  *) echo "a11y: unknown selection $3, use all, audit, audit-pages, audit-settings or functional" >&2; exit 2 ;;
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

# Why the tests of a result bundle failed, one line each with the test and the start of its failure text, into the
# job log: the result bundles are kept only when a job fails, not when a test passed on its run once more.
failures() {
  xcrun xcresulttool get test-results summary --path "$1" 2> /dev/null | jq -r --arg prefix "$2" '
    .testFailures[]? | "\($prefix)\(.testIdentifierString): \(.failureText | gsub("\\s+"; " ") | .[0:300])"' >&2 || true
}

# How busy this machine is while a device runs, every 10 s into `load_log` if A11Y_LOAD_LOG is 1: the seconds
# since the device started, the mean load of the last 1, 5 and 15 minutes, the share of the CPU that is idle and the
# share of the memory that is free. The script writes a line `# <step>` there when a step starts.
load_log=""
sampler=""
sample_load() {
  local start=$SECONDS idle free
  while :; do
    idle=$(top -l 2 -n 0 -s 1 | awk '/^CPU usage/ { idle = $7 } END { print idle }')
    free=$(memory_pressure -Q 2> /dev/null | awk '/free percentage/ { print $NF }')
    echo "$((SECONDS - start)) $(sysctl -n vm.loadavg | awk '{print $2, $3, $4}') ${idle:-?} ${free:-?}" >> "$load_log"
    sleep 9
  done
}
step() { echo "# $1 at $((SECONDS - started)) s" >> "$load_log"; }
stop_sampler() {
  if [ -n "$sampler" ]; then
    kill "$sampler" 2> /dev/null || true
    wait "$sampler" 2> /dev/null || true
    sampler=""
  fi
}
trap 'stop_sampler; shutdown_simulator' EXIT

# One run of the given tests into a result bundle of its own, which must not exist yet. A test runner that crashes
# before the tests start, as it does at times on a busy machine, gets a second start; the log of the first stays.
run_tests() {
  local bundle="$1" log="$2" attempt
  shift 2
  for attempt in 1 2; do
    rm -rf "$bundle"
    if xcodebuild test-without-building -project "$project" -scheme KV4PHT "${target[@]}" "$@" \
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
  rm -f "$retry_log" "$results/$device"*" not started.log"
  bundle="$results/runs/$run/$device.xcresult"
  retry_bundle="$results/runs/$run/$device retry.xcresult"
  mkdir -p "$results/runs/$run"
  started=$SECONDS
  stop_sampler # of a device that stopped early
  load_log=/dev/null
  if [ "${A11Y_LOAD_LOG:-}" = 1 ]; then
    load_log="$results/$device load.log"
    echo "# seconds, load of 1, 5 and 15 minutes, idle CPU, free memory, on $(sysctl -n hw.ncpu) cores" > "$load_log"
    sample_load &
    sampler=$!
  fi
  step build
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
  # Built first, and only then a simulator started: beside a new simulator, the build took several times as long.
  if ! xcodebuild build-for-testing -project "$project" -scheme KV4PHT "${target[@]}" \
    > "$results/$device build.log" 2>&1; then
    echo "a11y: the build for $device failed, see $results/$device build.log" >&2
    status=1
    continue
  fi
  if [ -n "$booted" ]; then
    step boot
    xcrun simctl bootstatus "$udid" -b > /dev/null
  fi
  step warm-up
  # The first launch of the app on its own, once more if it fails: a launch that fails on a fresh machine then does not
  # fail the first test of the selection. The run goes on either way; its tests tell whether the app starts.
  for attempt in 1 2; do
    warm_bundle="$results/runs/$run/$device warm-up $attempt.xcresult"
    if run_tests "$warm_bundle" "$results/$device warm-up.log" -only-testing:"$warm_up"; then
      break
    fi
    echo "a11y: the app did not start on $device at warm-up $attempt" >&2
    failures "$warm_bundle" "a11y: failed on $device at warm-up $attempt: "
  done
  # A test that fails runs once more, in a new test runner, and only that test: once the run of the whole selection is
  # over, its result bundle names the tests that failed.
  step tests
  if ! run_tests "$bundle" "$log" "${tests[@]}"; then
    step retry
    failures "$bundle" "a11y: failed on $device: "
    retry=()
    while IFS= read -r test; do
      [ "$test" = all ] && retry=("${tests[@]}") && break
      retry+=("$test")
    done < <(failed_tests "$bundle" 2> /dev/null || echo all)
    [ "${#retry[@]}" -gt 0 ] || retry=("${tests[@]}")
    echo "a11y: once more on $device: ${retry[*]#-only-testing:}" >&2
    if ! run_tests "$retry_bundle" "$retry_log" "${retry[@]}"; then
      echo "a11y: the UI tests failed on $device, see $retry_log" >&2
      failures "$retry_bundle" "a11y: failed on $device once more: "
      status=1
    fi
  fi
  echo "a11y: $device took $((SECONDS - started)) s"
  step end
  stop_sampler
  if [ "$load_log" != /dev/null ]; then
    echo "a11y: load on $device:"
    cat "$load_log"
  fi
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
