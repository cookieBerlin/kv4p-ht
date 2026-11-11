#!/usr/bin/env bash
# Installs the tools of `make site-check` on a Linux CI runner (ADR-0067): pandoc and lychee, pinned and checked.
# On a Mac: brew install pandoc lychee.
# Usage: site-tools.sh (run by `make site-tools`)
set -euo pipefail

pandoc_version=3.13
pandoc_sha256=7e3736f255090296ca5d1a14291a76b9b3c43cd385011b1621a4d0c16091a70f
lychee_version=0.24.2
lychee_sha256=1f4e0ef7f6554a6ed33dd7ac144fb2e1bbed98598e7af973042fc5cd43951c9a

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

curl -fsSL -o "$work/pandoc.deb" \
  "https://github.com/jgm/pandoc/releases/download/$pandoc_version/pandoc-$pandoc_version-1-amd64.deb"
echo "$pandoc_sha256  $work/pandoc.deb" | sha256sum -c -
sudo dpkg -i "$work/pandoc.deb"

curl -fsSL -o "$work/lychee.tar.gz" \
  "https://github.com/lycheeverse/lychee/releases/download/lychee-v$lychee_version/lychee-x86_64-unknown-linux-gnu.tar.gz"
echo "$lychee_sha256  $work/lychee.tar.gz" | sha256sum -c -
tar -xzf "$work/lychee.tar.gz" -C "$work"
sudo install "$(find "$work" -type f -name lychee | head -n 1)" /usr/local/bin/lychee

pandoc --version | head -n 1
lychee --version
