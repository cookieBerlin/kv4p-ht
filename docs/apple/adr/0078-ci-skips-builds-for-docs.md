# ADR-0078: CI skips the builds and tests when only documentation changed

- **Status:** Proposed
- **Date:** 2026-11-14
- **Amends:** [ADR-0017](0017-ci-change-detection.md) (which jobs the change detection starts)

## Context

[ADR-0017](0017-ci-change-detection.md) runs every Apple job as soon as a pull
request touches an Apple port path, and `docs/apple` is one. A pull request that
only changes the manual, an ADR or the changelog therefore builds the app, runs the
unit tests with coverage, and runs the UI tests on several devices
([ADR-0072](0072-ui-tests-in-parallel.md)): about an hour of macOS time for text
the app never compiles.

## Considered options

1. **Keep it** — every documentation change costs the full run.
2. **A second list of code paths** — a second file to keep in step with
   `apple-paths.txt`.
3. **The same paths, without documentation** — `make changed CODE=--code` checks
   the paths of `apple-paths.txt`, leaving out `docs/apple` and every Markdown
   file (`*.md`).

## Decision

Option 3.

- The `changes` job adds a `code` output from `make changed CODE=--code`.
- `lint`, `test`, `ios-build`, `app` and `ui-tests` run only if `code` is `true`;
  `vectors` likewise, together with the Android sources it is generated from.
- `privacy` and `site` still run on any Apple port change, as they check the
  documentation itself.
- `CHANGELOG.md` counts as documentation. The app shows it as text in fixed
  styles ([ADR-0069](0069-changelog.md)), its reader has unit tests with text of
  their own, and the website build reads it as well.
- If the base cannot be resolved, all jobs run, as before.

## Consequences

- A pull request that only changes documentation runs the privacy check and the
  website build, a few minutes instead of an hour.
- A Markdown file that the app or a build step uses for more than text in fixed
  styles would slip past the tests; such a file needs its own rule in
  `apple-changed.sh`.
- A job skipped as a whole reports once, without the names of its matrix entries.
  Required checks must therefore not name single matrix entries of a job that may
  be skipped.
