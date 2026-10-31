#!/usr/bin/env bash
# Prints the Apple port paths from apple-src/apple-paths.txt, one per line.
set -euo pipefail
grep -vE '^[[:space:]]*(#|$)' "$(dirname "$0")/../apple-paths.txt"
