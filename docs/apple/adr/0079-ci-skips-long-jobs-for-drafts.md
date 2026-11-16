# ADR-0079: CI skips the long jobs of a draft pull request

- **Status:** Proposed
- **Date:** 2026-11-16, runs on main let finish the same day
- **Amends:** [ADR-0072](0072-ui-tests-in-parallel.md) and
  [ADR-0078](0078-ci-skips-builds-for-docs.md) (which jobs run)

## Context

GitHub Actions starts a `pull_request` workflow for a draft as for any other pull
request: when it is opened, on each push and when it is reopened. A draft is
mostly a pull request that waits for another one, for example to be rebased on it,
or that is still being worked on. Each push to it still ran the app build, the iOS
build and the eight UI test jobs ([ADR-0072](0072-ui-tests-in-parallel.md)): about
three hours of macOS time for a change not yet meant to be merged.

## Considered options

1. **Keep it** and cancel the runs of a draft by hand, which is easily forgotten.
2. **`[skip ci]` in a commit message**, which skips the whole workflow for that
   push only and leaves the required checks pending.
3. **Skip the long jobs while the pull request is a draft**, and run them when it
   is marked ready for review.

## Decision

Option 3.

- `pull_request` also triggers on `ready_for_review`, besides the defaults
  `opened`, `synchronize` and `reopened`.
- `ios-build`, `app` and `ui-tests` run only if
  `github.event.pull_request.draft` is not `true`, in addition to the condition of
  [ADR-0078](0078-ci-skips-builds-for-docs.md). A push to `main` has no pull
  request, so it runs them as before.
- `lint`, `privacy`, `test`, `vectors` and `site` still run on a draft: they take a
  few minutes and catch most mistakes early.
- A new push to a pull request cancels its run before, as it did; a run on `main` is
  no longer cancelled by the next merge, and the next one waits for it. Several merges
  in a row had left `main` without a single complete run, which a flaky test needs to
  tell it from a real failure.

## Consequences

- A push to a draft costs a few minutes of macOS time instead of about three hours.
- Marking a draft ready for review starts a full run. A pull request turned back
  into a draft keeps the results of its last run.
- `ios-build` is a required check. On a draft, GitHub reports it as skipped, which
  counts as passed; a draft cannot be merged, and the run that marking it ready
  starts reports the check anew.
- Merges in quick succession queue their runs on `main`; GitHub keeps only the newest
  waiting one, so the runner time grows by one run at most.
- A draft shows no UI test results. To see them for a draft, mark it ready for
  review.
