#!/usr/bin/env bash
# Prints "true" if <base>...<head> touches an Apple port path, else "false".
# Prints "true" if the base cannot be resolved (e.g. a new branch), so the
# Apple jobs run rather than being skipped by mistake.
# With --oracle, the Android sources of the test vectors count as well.
# With --code, Markdown files and docs/apple do not count: a change that only
# touches documentation needs no build and no tests (ADR-0078).
# Usage: apple-changed.sh <base-ref> [<head-ref>] [--oracle] [--code]
set -euo pipefail

base="${1:-}"
head="${2:-HEAD}"
oracle=""
excludes=()
for option in "${@:3}"; do
  case "$option" in
    --oracle) oracle=--oracle ;;
    --code) excludes=(':(exclude)docs/apple' ':(exclude,glob)**/*.md') ;;
    "") ;;
    *) echo "apple-changed.sh: unknown option $option" >&2; exit 2 ;;
  esac
done
paths=$("$(dirname "$0")/apple-paths.sh" $oracle)
cd "$(git rev-parse --show-toplevel)"

if [[ -z "$base" ]] || ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
  echo true
  exit 0
fi

# shellcheck disable=SC2086 # paths contain no spaces
if git diff --quiet "$base...$head" -- $paths ${excludes[@]+"${excludes[@]}"}; then
  echo false
else
  echo true
fi
