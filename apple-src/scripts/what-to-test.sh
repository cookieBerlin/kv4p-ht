#!/usr/bin/env bash
# Prints the text for "What to Test" in TestFlight: the open hardware tests of a platform (ADR-0035).
# Usage: what-to-test.sh <iOS|macOS> [test list, default ../docs/apple/hardware-tests.md]
set -euo pipefail

cd "$(dirname "$0")/.."
platform="$1"
list="${2:-../docs/apple/hardware-tests.md}"
case "$platform" in
  macOS) column=4 ;;
  iOS) column=5 ;;
  *)
    echo "what-to-test: unknown platform $platform" >&2
    exit 1
    ;;
esac

grep -q '^| \[HW-' "$list" || {
  echo "what-to-test: no tests in $list" >&2
  exit 1
}
open=$(awk -F'|' -v column="$column" '/^\| \[HW-/ && $column ~ /⬜/ {
  id = $2; title = $3
  sub(/^ *\[/, "", id); sub(/\].*/, "", id)
  gsub(/^ +| +$/, "", title)
  print id " " title
}' "$list")
if [[ -z "$open" ]]; then
  echo "All hardware tests are done."
  exit 0
fi
echo "Open hardware tests. Please report results with the test ID."
echo "Steps: https://github.com/cookieBerlin/kv4p-ht/blob/main/docs/apple/hardware-tests.md"
echo
echo "$open"
