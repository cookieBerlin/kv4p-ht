#!/usr/bin/env bash
# Turns "## Unreleased" of the changelog into the section of a TestFlight build, with a new, empty "Unreleased" above
# it (ADR-0069). Run by release-testflight.sh before it archives, so that the app bundles the section of its build.
# Usage: changelog-release.sh <changelog> <version> <build> <date, YYYY-MM-DD>
set -euo pipefail

file="$1" version="$2" build="$3" date="$4"
if ! grep -qx '## Unreleased' "$file"; then
  echo "changelog: no \"## Unreleased\" in $file" >&2
  exit 1
fi
if grep -qF "($build)" "$file"; then
  echo "changelog: $file already has a section for the build $build" >&2
  exit 1
fi
awk -v section="## $version ($build) – $date" '
  !done && $0 == "## Unreleased" { print; print ""; print section; done = 1; next }
  { print }
' "$file" >"$file.new"
mv "$file.new" "$file"
echo "changelog: Unreleased is now \"$version ($build) – $date\" in $file"
