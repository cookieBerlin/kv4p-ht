# ADR-0072: UI tests in parallel jobs, one simulator each

- **Status:** Proposed
- **Date:** 2026-11-13

## Context

The CI job `a11y` ran all UI tests, the accessibility audit
([ADR-0062](0062-accessibility-audit.md)) and the functional tests, on an iPhone and
then an iPad simulator, on one machine. A run took about an hour. Its last two runs
failed: on the iPhone, the audit timed out while evaluating a UI query after
800–1000 s; on the iPad, the test runner crashed before the tests started ("never
finished bootstrapping"). The same crash happened locally while several simulators ran
at once. The job is not a required check, so the failures went unnoticed.

The iPhone Duo ([ADR-0071](0071-iphone-duo.md)) adds a third device whose layout
differs from both.

## Considered options

1. **One job, as before, with the iPhone Duo added.** Longer still, and the same load.
2. **A matrix of GitHub-hosted jobs: one per device and per selection of tests.**
   Each machine runs one simulator. Chosen.
3. **Self-hosted runners on the maintainer's Mac.** The Mac would carry the load
   anyway. In a public repository, pull requests from forks could run code on it,
   which GitHub advises against. Rejected.

## Decision

- **`scripts/a11y.sh` takes a selection:** `all` (the default), `audit` (only
  `AccessibilityAuditTests`) or `functional` (every other UI test). `make a11y` passes
  it as `UI_TESTS`. The devices are the iPhone 18 Pro, the iPad Pro 11-inch (M5) and
  the iPhone Duo.
- **CI job `ui-tests`:** a matrix of the three devices and the two selections, six
  jobs side by side, `fail-fast: false`, each with its own artifact.
- **Retries:** a failing test runs once more (`-retry-tests-on-failure
  -test-iterations 2`). A test runner that crashes before the tests start gets a
  second start.

## Consequences

- **Faster and steadier:** a run takes as long as its slowest job, about the audit on
  one device, rather than the sum of all.
- **Billing:** six macOS jobs per pull request. On a runner that is billed per minute,
  this costs about as many minutes as before, plus a build per job.
- **Folding:** the iPhone Duo runs folded, as it boots; unfolding cannot be scripted.
- **Required check:** once the functional jobs pass steadily, they should become
  required ([ADR-0016](0016-branch-protection.md)). That is the maintainer's decision.
