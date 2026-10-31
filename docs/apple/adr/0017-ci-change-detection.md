# ADR-0017: CI change detection instead of path filters

- **Status:** Accepted
- **Date:** 2026-10-31
- **Amends:** [ADR-0013](0013-ci-pr-gate.md) (workflow triggers)

## Context

[ADR-0013](0013-ci-pr-gate.md) path-filters `apple-ci.yml` to the Apple port
paths, and [ADR-0016](0016-branch-protection.md) makes its jobs required status
checks on `main`. A pull request that touches no Apple path (for example an
upstream sync of the Android app or firmware) never starts the workflow, so the
required checks never report and the pull request cannot be merged.

## Considered options

1. **Keep path filters, drop required checks** — removes the gate.
2. **Keep path filters, add a placeholder workflow with the same job names for
   the inverse paths** — duplicates job names and path lists.
3. **Run on every pull request; a cheap `changes` job decides whether the Apple
   jobs run** — skipped jobs report as successful, so required checks always
   resolve.

## Decision

Option 3.

- `apple-ci.yml` has no path filters. A `changes` job on `ubuntu-latest` runs
  `make changed`, which prints whether `BASE...HEAD_REF` touches an Apple port
  path. The macOS jobs `lint`, `privacy`, `test` and `ios-build` depend on it and
  run only if it prints `true`.
- If the base cannot be resolved (for example the first push of a branch), the
  Apple jobs run.
- The Apple port paths are listed once in `apple-src/apple-paths.txt`, used by
  both the change detection and the personal data check.

## Consequences

- Every pull request gets a cheap Linux job; macOS minutes are only used when
  Apple paths change.
- Pull requests without Apple changes merge with the Apple checks reported as
  skipped.
- New Apple port paths must be added to `apple-paths.txt`.
