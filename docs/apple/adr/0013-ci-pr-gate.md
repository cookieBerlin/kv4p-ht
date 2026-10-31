# ADR-0013: CI and pull request gate

- **Status:** Accepted
- **Date:** 2026-10-31
- **Amended by:** [ADR-0015](0015-build-layout-and-tooling.md), [ADR-0016](0016-branch-protection.md)

## Context

All tests must run as a GitHub Actions pull request gate. The rules from
[`CLAUDE.md`](../../../CLAUDE.md) (TDD, 100 % coverage, no personal data, docs kept
current) should be enforced automatically where possible. Local and CI commands
must not diverge (DRY).

## Considered options

1. **GitHub Actions on `macos-latest` (Apple Silicon) calling `make ci`**.
2. **Xcode Cloud** — Apple-native, but separate configuration and accounts.
3. **Self-hosted runner** — fast, but ties CI to a private machine.

## Decision

Option 1. Workflow `.github/workflows/apple-ci.yml`:

- Triggers: `pull_request` and `push` to `main`, path-filtered to `apple-src/**`,
  `tools/test-vectors/**`, `docs/apple/**`, `CLAUDE.md` and the workflow itself.
- Jobs (each a required status check):
  1. **test** — `make coverage` (build, `swift test`, 100 % gate, coverage report as artifact).
  2. **vectors** — set up JDK 17, `make vectors`, fail if `git diff` is not empty.
  3. **lint** — `make lint` (SwiftLint, SwiftFormat).
  4. **privacy** — scan the diff for e-mail addresses, phone numbers and other
     personal data patterns (allow-list for placeholders such as `N0CALL`,
     `example.com`, GitHub noreply addresses).
  5. **ios-build** — compile packages and app for iOS (from phase 1, compile only).
- Branch protection on `main` of the fork requires all checks and a pull request.

## Consequences

- One `Makefile` defines all steps; the workflow only calls targets.
- Pushing workflow files needs a GitHub token with the `workflow` scope.
- macOS runner minutes are more expensive; path filters and caching keep usage low.
