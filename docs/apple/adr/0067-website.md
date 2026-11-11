# ADR-0067: Website on GitHub Pages

- **Status:** Proposed
- **Date:** 2026-11-11

## Context

The Apple app lives in a fork, and no merge back into the original project is planned for now. It needs a page of
its own: a public TestFlight link, a feature list, the FAQ and the manual, and later the App Store link. App Store
Connect also asks for a privacy policy URL and a support URL. The original project's site (`website-src/`) is
its own and stays as it is.

Facts that bound the choice:

- **GitHub Pages** publishes from a branch only from `/` or `/docs`, not from `docs/apple/`. Publishing all of
  `/docs` would also publish the planning documents and ADRs. A GitHub Actions workflow can publish any folder.
- **One place:** the FAQ and the manual are kept in `docs/apple/` and read on GitHub (CLAUDE.md rule 4). Their
  links point to other files of the repository, which are not part of a site.
- **Privacy:** no personal data (rule 6). The app's privacy label promises no tracking, so the site should not
  track either.
- **CI:** jobs only call Makefile targets (ADR-0013).

## Decision

- **Source:** `docs/apple/site/` holds the pages written for the site (`index.md`, `privacy.md`, `support.md`),
  the template, the style sheet, `site.yaml` with the values every page uses (name, repository, TestFlight link),
  and `links.lua`. The FAQ and the manual are built from `docs/apple/` as they are.
- **Build:** `make site` runs `scripts/site.sh`, which renders every page with pandoc into `apple-src/.build/site`.
  The FAQ and the manual are read as GitHub Flavored Markdown, so their anchors match GitHub's. `links.lua` turns
  a link to a page of the site into its `.html` page, a link to any other file into its GitHub URL, and
  `$name$` at the start of a link into the value from `site.yaml`. The app icon comes from the asset catalogue.
- **Check:** `make site-check` builds the site and checks its links and anchors with lychee, without the
  internet. Apple CI runs it in the `site` job for every pull request that touches an Apple path. `make
  site-tools` installs pandoc and lychee, pinned and checked against their SHA-256, on the Linux runner.
- **Publish:** `.github/workflows/apple-pages.yml` builds and checks the site on each push to `main` that changes
  it, and publishes it with GitHub's Pages actions to `https://cookieberlin.github.io/kv4p-ht/`. The repository's
  Pages source is *GitHub Actions*.
- **Look:** after the original project's site: a black hero, its accent colour `#AD5642`, light and dark. The
  system font, no web fonts.
- **Privacy:** no cookies, no analytics, nothing loaded from other servers. The privacy page states what the
  developer collects, which is nothing, and links to the FAQ for what the app sends where. No custom domain.
- **Naming:** the site uses the App Store name *kv4p HT (CookieBerlin)*, says that the app is an unofficial port,
  and links to the original project for the radio.

## Consequences

- The FAQ and the manual reach the site on the next push to `main`, without being copied.
- A link in them that the site cannot resolve fails `make site-check`, and with it the pull request.
- The privacy page sums up the FAQ answer on personal data; a change to what the app sends updates both.
- The TestFlight link is in `site.yaml` and in the manual's installation section.
- The site's pandoc version can differ from a developer's; the CI build is the one published.
