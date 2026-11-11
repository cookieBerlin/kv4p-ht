#!/usr/bin/env bash
# Builds the website of the Apple app (ADR-0067) with pandoc: the pages of docs/apple/site and, as they are,
# the FAQ and the manual of docs/apple. Links to other files of the repository point to GitHub.
# Usage: site.sh <output folder> (run by `make site`)
set -euo pipefail

out="$1"
root="$(git rev-parse --show-toplevel)"
site="$root/docs/apple/site"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
rm -rf "${out:?}"/*
mkdir -p "$out/img"

cp "$site/style.css" "$out/"
cp "$root/apple-src/App/KV4PHT/Assets.xcassets/AppIcon.appiconset/AppIcon.png" "$out/img/app-icon.png"
if [[ -d "$site/img" ]]; then cp "$site/img/"* "$out/img/"; fi

# page <source, repository-relative> <reader> <output name> [pandoc options]
page() {
  local source="$1" reader="$2" name="$3"
  shift 3
  pandoc "$root/$source" --from "$reader" --to html5 --standalone \
    --template "$site/template.html" --metadata-file "$site/site.yaml" \
    --metadata srcdir="$(dirname "$source")" --lua-filter "$site/links.lua" \
    "$@" --output "$out/$name"
}

# The FAQ and the manual are read as on GitHub, so their anchors match.
page docs/apple/faq.md gfm faq.html --metadata pagetitle=FAQ \
  --metadata description="Questions and answers about the kv4p HT app for iPhone, iPad and Mac."
page docs/apple/manual.md gfm manual.html --metadata pagetitle=Manual \
  --metadata description="User manual of the kv4p HT app for iPhone, iPad and Mac."
for source in "$site"/*.md; do
  name="$(basename "$source" .md)"
  page "docs/apple/site/$name.md" markdown "$name.html"
done
echo "site: $out"
