#!/usr/bin/env bash
# Fails unless every source file under Packages/*/Sources has 100 % line
# coverage, except files listed in coverage-exclusions.txt (ADR-0011).
# Usage: coverage-gate.sh <llvm-cov JSON from `swift test --show-codecov-path`>
set -euo pipefail

json="${1:?usage: coverage-gate.sh <codecov.json>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
exclusions="$root/coverage-exclusions.txt"

excluded=$(grep -vE '^\s*(#|$)' "$exclusions" 2>/dev/null || true)

report=$(jq -r --arg root "$root/" --arg excluded "$excluded" '
  ($excluded | split("\n") | map(select(length > 0))) as $ex
  | [.data[0].files[]
     | (.filename | ltrimstr($root)) as $f
     | select($f | test("^Packages/[^/]+/Sources/"))
     | select(($ex | index($f)) | not)
     | {file: $f, count: .summary.lines.count, covered: .summary.lines.covered}]
  | (map(.count) | add // 0) as $total
  | (map(.covered) | add // 0) as $covered
  | (map(select(.covered < .count) | "  \(.file): \(.covered)/\(.count) lines")) as $gaps
  | "\($covered) \($total)", $gaps[]
' "$json")

read -r covered total <<<"$(head -n1 <<<"$report")"
gaps=$(tail -n +2 <<<"$report")

if [[ "$total" -eq 0 ]]; then
  echo "coverage: no source files found" >&2
  exit 1
fi

echo "coverage: $covered/$total lines"
if [[ "$covered" -ne "$total" ]]; then
  echo "coverage: below 100 %, uncovered lines in:" >&2
  echo "$gaps" >&2
  exit 1
fi
echo "coverage: 100 %"
