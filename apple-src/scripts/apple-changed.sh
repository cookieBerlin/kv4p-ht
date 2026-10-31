#!/usr/bin/env bash
# Prints "true" if <base>...<head> touches an Apple port path, else "false".
# Prints "true" if the base cannot be resolved (e.g. a new branch), so the
# Apple jobs run rather than being skipped by mistake.
# Usage: apple-changed.sh <base-ref> [<head-ref>]
set -euo pipefail

base="${1:-}"
head="${2:-HEAD}"
paths=$("$(dirname "$0")/apple-paths.sh")
cd "$(git rev-parse --show-toplevel)"

if [[ -z "$base" ]] || ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
  echo true
  exit 0
fi

# shellcheck disable=SC2086 # paths contain no spaces
if git diff --quiet "$base...$head" -- $paths; then
  echo false
else
  echo true
fi
