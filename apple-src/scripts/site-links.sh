#!/usr/bin/env bash
# Checks that every link of the website to another site opens in a new tab and says so (ADR-0067):
# target="_blank", rel="noopener", and the hidden hint "(opens in a new tab)" for screen readers.
# Usage: site-links.sh <site folder> (run by `make site-check`)
set -euo pipefail

perl -0777 -ne '
  while (m{(<a\b[^>]*\bhref="https?://[^"]*"[^>]*>)(.*?)</a>}gs) {
    my ($tag, $text) = ($1, $2);
    next if $tag =~ /\btarget="_blank"/ && $tag =~ /\brel="noopener"/
      && $text =~ m{<span class="new-tab">\s*\(opens in a new tab\)</span>};
    (my $shown = $tag) =~ s/\s+/ /g;
    print "$ARGV: $shown\n";
    $failed = 1;
  }
  END { exit($failed ? 1 : 0) }
' "$1"/*.html || {
  echo "site-links: the links above leave the site without opening a new tab and saying so" >&2
  exit 1
}
echo "site-links: every link to another site opens a new tab"
