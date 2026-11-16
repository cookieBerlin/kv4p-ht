# ADR-0072: UI tests in parallel jobs, one simulator each

- **Status:** Proposed
- **Date:** 2026-11-13, the Mac added 2026-11-15, retries of the failed tests only and the result bundles of a failed job 2026-11-16

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

The Mac's UI tests ran by hand only (`make a11y-mac`), as they take over the mouse and
the keyboard. A trial on GitHub's macOS runner (`xcode-27`, macOS 27) showed that they
run there as well: XCTest drives the app on the runner's own desktop, which nobody
uses, without asking for automation mode, and the screenshots show the app's window.
The trial also found the failures the Mac had locally, a crash and the audit's
findings, which were fixed before the jobs were added.

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
  the iPhone Duo, and the Mac, which runs the app itself.
- **CI job `ui-tests`:** a matrix of the four devices and the two selections, eight
  jobs side by side, `fail-fast: false`, each with its own artifact: the findings, the
  logs and the screenshots. A job that fails also keeps its result bundles for a week,
  with the crash reports of a test runner that exited in the middle of a test; at up
  to some 170 MB each, a job that passes does not.
- **Retries:** a failing test runs once more, and only that test: once the run of the
  whole selection is over, `scripts/a11y.sh` reads the failed tests from its result
  bundle and starts a second run of just those, in a new test runner. A failure that
  names no test, such as a runner that crashed between two tests, runs the whole
  selection once more. A test runner that crashes before the tests start gets a
  second start, also when it times out while preparing to run the tests.
- **One simulator at a time:** a simulator the script started is shut down once its
  device is done.

## Consequences

- **Faster and steadier:** a run takes as long as its slowest job, about the audit on
  one device, rather than the sum of all.
- **Retries cost only what failed:** with `-retry-tests-on-failure -test-iterations 2`,
  as before, Xcode 27.1 ran the whole selection a second time after one failure. On
  CI that happened in about half of the iPhone and iPad jobs and in most of the iPhone
  Duo's, and cost 10–17 minutes each time.
- **The simulator still starts after the build:** booting it beside the build
  (`build-for-testing`, then `test-without-building`) was tried in three CI runs. A new
  simulator keeps the machine busy for minutes after it reports its start: beside it,
  the build took 6–19 minutes rather than about 1.5. Booted only after the build, the
  first launch of the app timed out twice and a test runner did not start twice. Three
  runs did not show a clear gain, so `xcodebuild test` builds and boots as before.
- **Billing:** eight macOS jobs per pull request that changes more than documentation
  ([ADR-0078](0078-ci-skips-builds-for-docs.md)). On a runner that is billed per
  minute, this costs about as many minutes as before, plus a build per job.
- **Folding:** the iPhone Duo runs folded, as it boots; unfolding cannot be scripted.
- **The Mac in CI:** `make a11y-mac` is still there for a run on the maintainer's
  Mac, but a pull request no longer needs one.
- **Required check:** once the functional jobs pass steadily, they should become
  required ([ADR-0016](0016-branch-protection.md)). That is the maintainer's decision.
