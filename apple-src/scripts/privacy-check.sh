#!/usr/bin/env bash
# Fails if Apple port files or commit metadata contain personal data
# (CLAUDE.md rule 6, ADR-0013). Checks e-mail addresses in tracked files and
# author/committer e-mails of commits in the given range.
# Usage: privacy-check.sh [<base-ref>]   (default base: upstream/main or origin/main)
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
cd "$repo"

base="${1:-}"
if [[ -z "$base" ]]; then
  for candidate in upstream/main origin/main; do
    if git rev-parse --verify --quiet "$candidate" >/dev/null; then base="$candidate"; break; fi
  done
fi

paths=(CLAUDE.md apple-src docs/apple tools .github/workflows/apple-ci.yml)
allowed='(noreply@anthropic\.com|noreply@github\.com|@users\.noreply\.github\.com|@example\.(com|org|net))$'
email='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
status=0

existing=()
for p in "${paths[@]}"; do [[ -e "$p" ]] && existing+=("$p"); done

hits=$(git grep -nIoE "$email" -- "${existing[@]}" | grep -vE "$allowed" || true)
if [[ -n "$hits" ]]; then
  echo "privacy: e-mail addresses found in files:" >&2
  echo "$hits" >&2
  status=1
fi

if [[ -n "$base" ]]; then
  authors=$(git log --format='%ae%n%ce' "$base..HEAD" | sort -u | grep -vE "$allowed" || true)
  if [[ -n "$authors" ]]; then
    echo "privacy: commits in $base..HEAD use non-anonymous e-mails:" >&2
    echo "$authors" >&2
    status=1
  fi
fi

[[ "$status" -eq 0 ]] && echo "privacy: ok"
exit "$status"
