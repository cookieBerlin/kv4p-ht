# ADR-0010: Repository structure

- **Status:** Accepted
- **Date:** 2026-10-31

## Context

The Apple app is developed in a fork of the upstream repository with the goal of
contributing it back. Firmware, Android app and website already live side by side
in one repository. The Android and firmware directories must stay untouched.

## Considered options

1. **Same repository, new top-level directories** — `apple-src/`, `docs/apple/`,
   `tools/test-vectors/`, `.github/workflows/apple-ci.yml`.
2. **Separate repository** — clean separation, but the protocol source of truth
   and the test oracle would live in another repository.

## Decision

Option 1. The only change to existing files is a link from the root `FAQ.md` to
[`docs/apple/faq.md`](../faq.md). The bundle identifier
`io.github.cookieberlin.kv4pht` is defined once in `apple-src/Config/Base.xcconfig`
so upstream can override it without code changes.

## Consequences

- Protocol changes in firmware/Android and the Apple vectors move in the same
  pull request history.
- Apple CI is path-filtered so it does not run for unrelated changes, and existing
  workflows are not affected.
- Upstream merges stay conflict-free because existing directories are untouched.
