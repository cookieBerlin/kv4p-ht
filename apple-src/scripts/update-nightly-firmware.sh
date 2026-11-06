#!/usr/bin/env bash
# Replaces the bundled nightly firmware with the current nightly release of the original project (ADR-0049), after
# checking GitHub's digest of the file. Run on purpose only: a new image needs a hardware test before it ships.
# The project comes from the `upstream` remote. Needs gh and jq.
set -euo pipefail
cd "$(dirname "$0")/.."

name=firmware-nightly.bin
directory=App/Firmware
repo="$(git remote get-url upstream | sed -E 's#.*github\.com[:/]##; s#\.git$##')"

asset="$(gh api "repos/$repo/releases/tags/nightly" --jq ".assets[] | select(.name == \"$name\")")"
digest="$(jq -r '.digest // empty' <<<"$asset")"
expected="${digest#sha256:}"
if [[ -z "$expected" ]]; then
  echo "nightly firmware: GitHub publishes no digest for $name" >&2
  exit 1
fi
# The upload time is the build time: the release date stays that of the first nightly.
built="$(jq -r '.updated_at' <<<"$asset" | sed -E 's/^([0-9-]+)T([0-9]{2}:[0-9]{2}).*/\1 \2 UTC/')"
commit="$(gh api "repos/$repo/commits/nightly" --jq .sha)"

download="$(mktemp -d)"
trap 'rm -rf "$download"' EXIT
gh release download nightly --repo "$repo" --pattern "$name" --dir "$download"
actual="$(shasum -a 256 "$download/$name" | cut -d' ' -f1)"
if [[ "$actual" != "$expected" ]]; then
  echo "nightly firmware: the checksum of the download differs from GitHub's digest" >&2
  exit 1
fi

mkdir -p "$directory"
mv "$download/$name" "$directory/$name"
jq -n --arg commit "$commit" --arg built "$built" --arg sha256 "$actual" \
  '{commit: $commit, built: $built, sha256: $sha256}' >"$directory/firmware-nightly.json"
echo "nightly firmware: $built, commit ${commit:0:7}, SHA-256 $actual"
