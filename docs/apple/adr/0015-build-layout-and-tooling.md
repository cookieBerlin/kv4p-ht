# ADR-0015: Build layout and lint tooling

- **Status:** Accepted
- **Date:** 2026-10-31
- **Amends:** [ADR-0013](0013-ci-pr-gate.md) (lint job tooling)

## Context

[ADR-0013](0013-ci-pr-gate.md) named SwiftLint and SwiftFormat for the lint job,
and the architecture lists one Swift package per module. While setting up the
foundation (milestone 1.0) two facts became relevant:

- Xcode ships `swift format` (swift-format) with the toolchain; SwiftLint and
  the third-party SwiftFormat would be extra dependencies to install and pin
  locally and in CI.
- Separate `Package.swift` files per module would need one `swift test` run and
  one coverage report per package, and the coverage gate would have to merge them.

## Considered options

1. **SwiftLint + SwiftFormat, one package per module** — as planned; more tools,
   more CI steps, merged coverage reports.
2. **Bundled `swift format`, one SwiftPM package (`apple-src/Package.swift`) with
   one target per module** — module sources keep the planned folder layout
   (`Packages/<Module>/Sources|Tests`), one test run, one coverage report.

## Decision

Option 2.

- `apple-src/Package.swift` declares every module as a target with an explicit
  `path` under `Packages/<Module>/`. Module boundaries are still enforced by
  target dependencies.
- Linting and formatting use `swift format` with `apple-src/.swift-format`
  (`make lint`, `make format`).
- Targets are added when their milestone starts, not as empty skeletons.

## Consequences

- No third-party build tools; CI only needs Xcode and `jq` (preinstalled on
  GitHub macOS runners).
- If a rule that only SwiftLint offers becomes necessary, a new ADR can add it.
- Splitting a module into its own package later is a mechanical change.
