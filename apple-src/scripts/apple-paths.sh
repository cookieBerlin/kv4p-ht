#!/usr/bin/env bash
# Prints the Apple port paths from apple-src/apple-paths.txt, one per line.
# With --oracle, also prints the Android sources the test vectors are
# generated from (tools/test-vectors/oracle-sources.txt) and the Android build
# file the app version is generated from (ADR-0037).
# Usage: apple-paths.sh [--oracle]
set -euo pipefail
here="$(dirname "$0")"
lists=("$here/../apple-paths.txt")
[[ "${1:-}" == "--oracle" ]] && lists+=("$here/../../tools/test-vectors/oracle-sources.txt")
cat "${lists[@]}" | grep -vE '^[[:space:]]*(#|$)'
if [[ "${1:-}" == "--oracle" ]]; then
  echo android-src/KV4PHT/app/build.gradle
fi
