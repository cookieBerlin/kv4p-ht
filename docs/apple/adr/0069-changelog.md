# ADR-0069: Changelog

- **Status:** Proposed
- **Date:** 2026-11-11

## Context

Testers get a TestFlight build every now and then and cannot tell what changed since the last one. *What to Test*
lists the open hardware tests ([ADR-0035](0035-testflight.md)), not what is new. The app, the website and GitHub should
say the same, and the project keeps every piece of knowledge in one place (CLAUDE.md, rule 4).

## Considered options

1. **Generated from the pull requests:** their titles are written for developers, and many have no change a user
   notices.
2. **One hand-written Markdown file, bundled by the app:** written for users, read on GitHub, shown on the website
   and in the app.

## Decision

Option 2.

- **Source:** `apple-src/App/KV4PHT/CHANGELOG.md`. The app's folder is synchronized with the Xcode project, so the
  file is bundled without a change to the project. On top *Unreleased*, below a section for each TestFlight build,
  such as `## 0.1 (20261101.2216) – 2026-11-01`, newest first, grouped as *Added*, *Changed* and *Fixed*, with what
  users notice only. A fix of something that no uploaded build had is not listed.
- **Entries:** every pull request with a change a user notices adds it under *Unreleased* (CLAUDE.md, rule 8).
- **Release:** `make testflight` runs `scripts/changelog-release.sh` before it archives: *Unreleased* becomes the
  section of the build it uploads, with the app version, the build ID and the UTC date, and an empty *Unreleased* goes
  above it. So the app bundles the section of its own build. The script refuses a changelog without *Unreleased*, or
  with a section of that build already. The changed file is committed afterwards in a pull request; a dry run puts it
  back. *What to Test* stays as it is.
- **Reader:** `Changelog` in `KV4PRadio` reads headings, list items and paragraphs, and keeps their inline Markdown,
  which the view shows with `AttributedString`. It finds the section of a build by the build ID in parentheses.
- **In the app:** *What's New* in About shows the whole changelog. At the first start of a new build, the app offers
  that build's section once; after the first installation, it offers nothing. The build seen last is kept in the
  app's local defaults, not synced. A build without a section of its own, such as one from Xcode, offers nothing.
  VoiceOver knows the headings, and the accessibility audit checks the view (ADR-0062).
- **Website:** `scripts/site.sh` builds `changelog.html` from the same file, beside the manual and the FAQ
  ([ADR-0067](0067-website.md)); a link to the file becomes that page.
- **Content so far:** the first build, 0.1 (20261101.2216), was uploaded from `main` after pull request 35; what was
  merged up to it is in its section, the rest under *Unreleased*.

## Consequences

- Each pull request with a visible change has one more file to update, next to the manual and the FAQ.
- A tester who updates from a build older than this one is offered nothing once, as no build was seen before;
  *What's New* in About has it all.
- The commit in About names the commit the build came from; the changelog's new section is committed after the
  upload.
