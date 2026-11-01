#!/usr/bin/env bash
# Fails if Apple port files or commit metadata contain personal data
# (CLAUDE.md rule 6, ADR-0013). Checks e-mail addresses in tracked files and
# author/committer e-mails of commits in <base>..<head>.
# Findings are reported by location only and never echoed, because CI logs
# may be public.
# Usage: privacy-check.sh [<base-ref> [<head-ref>]]
#   default base: upstream/main or origin/main; default head: HEAD
set -euo pipefail

paths=()
while IFS= read -r p; do paths+=("$p"); done < <("$(dirname "$0")/apple-paths.sh")
# Vendored third-party code keeps its authors' notices unmodified (ADR-0027).
while IFS= read -r p; do paths+=(":(exclude)$p"); done \
  < <(grep -vE '^[[:space:]]*(#|$)' "$(dirname "$0")/../privacy-exclusions.txt")
cd "$(git rev-parse --show-toplevel)"

base="${1:-}"
head="${2:-HEAD}"
if [[ -z "$base" ]]; then
  for candidate in upstream/main origin/main; do
    if git rev-parse --verify --quiet "$candidate" >/dev/null; then base="$candidate"; break; fi
  done
fi

allowed='(noreply@anthropic\.com|noreply@github\.com|@users\.noreply\.github\.com|@example\.(com|org|net))$'
email='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
status=0

existing=()
for p in "${paths[@]}"; do [[ -e "$p" || "$p" == ":(exclude)"* ]] && existing+=("$p"); done

# git grep -o prints "file:line:match"; keep only the location.
hits=$(git grep -nIoE "$email" -- "${existing[@]}" | grep -vE "$allowed" | cut -d: -f1,2 | sort -u || true)
if [[ -n "$hits" ]]; then
  echo "privacy: non-placeholder e-mail addresses found at:" >&2
  echo "$hits" >&2
  status=1
fi

if [[ -n "$base" ]]; then
  commits=$(git log --format='%h %ae %ce' "$base..$head" \
    | ALLOWED="$allowed" awk '$2 !~ ENVIRON["ALLOWED"] || $3 !~ ENVIRON["ALLOWED"] { print $1 }' || true)
  if [[ -n "$commits" ]]; then
    echo "privacy: commits in $base..$head use non-anonymous author/committer e-mails:" >&2
    echo "$commits" >&2
    status=1
  fi
fi

[[ "$status" -eq 0 ]] && echo "privacy: ok"
exit "$status"
