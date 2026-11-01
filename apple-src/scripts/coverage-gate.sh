#!/usr/bin/env bash
# Fails unless every source file under Packages/*/Sources has 100 % line
# coverage, except files listed in coverage-exclusions.txt (ADR-0011; an entry
# ending in / excludes a directory), and
# unless every module has coverage data.
# Usage: coverage-gate.sh <bin path from `swift build --show-bin-path`>
#
# `swift test --show-codecov-path` only exports the first test bundle, so the
# report is exported here from the merged profile and every test bundle.
set -euo pipefail

bin="${1:?usage: coverage-gate.sh <bin path>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
exclusions="$root/coverage-exclusions.txt"

excluded=$(grep -vE '^\s*(#|$)' "$exclusions" 2>/dev/null || true)

objects=()
for bundle in "$bin"/*Tests.xctest; do
  objects+=(-object "$bundle/Contents/MacOS/$(basename "$bundle" .xctest)")
done
json=$(xcrun llvm-cov export -summary-only -instr-profile "$bin/codecov/default.profdata" "${objects[@]}")

report=$(jq -r --arg root "$root/" --arg excluded "$excluded" '
  ($excluded | split("\n") | map(select(length > 0))) as $ex
  | [.data[0].files[]
     | (.filename | ltrimstr($root)) as $f
     | select($f | test("^Packages/[^/]+/Sources/"))
     | select(any($ex[]; . as $e | if ($e | endswith("/")) then ($f | startswith($e)) else $f == $e end) | not)
     | {file: $f, count: .summary.lines.count, covered: .summary.lines.covered}]
  | (map(.count) | add // 0) as $total
  | (map(.covered) | add // 0) as $covered
  | (map(select(.covered < .count) | "  \(.file): \(.covered)/\(.count) lines")) as $gaps
  | "\($covered) \($total)", $gaps[]
' <<<"$json")

files=$(jq -r --arg root "$root/" '.data[0].files[].filename | ltrimstr($root)' <<<"$json")
missing=""
for module in "$root"/Packages/*/Sources/*/; do
  module="${module#"$root/"}"
  # Modules whose files are all excluded (e.g. a tool's entry point) need no data.
  covered_files=$(cd "$root" && find "$module" -name '*.swift' | grep -vxF "$excluded" || true)
  [[ -z "$covered_files" ]] && continue
  grep -q "^$module" <<<"$files" || missing+="  $module"$'\n'
done
if [[ -n "$missing" ]]; then
  echo "coverage: no coverage data for:" >&2
  printf '%s' "$missing" >&2
  exit 1
fi

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
