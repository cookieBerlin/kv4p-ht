# ADR-0072: UI tests in parallel jobs, one simulator each

- **Status:** Proposed
- **Date:** 2026-11-13, the Mac added 2026-11-15, retries of the failed tests only, the result bundles of a failed job, the audit in two parts, the build before the boot, the warm-up and the load log 2026-11-16, the failures of a run once more in the job log 2026-11-17

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
  `AccessibilityAuditTests`), `audit-pages` or `audit-settings` (one of its two parts),
  or `functional` (every other UI test). `make a11y` passes it as `UI_TESTS`. The devices are the iPhone 18 Pro, the iPad Pro 11-inch (M5) and
  the iPhone Duo, and the Mac, which runs the app itself.
- **The audit in two parts:** each text size has a test for the pages (the memories,
  the packets, the chats and the map, with their panels) and one for the settings (each
  of their pages, and What's New; on the Mac also About). Each part starts the app on
  its own.
- **CI job `ui-tests`:** a matrix of the four devices and three selections,
  `functional`, `audit-pages` and `audit-settings`: twelve jobs side by side, `fail-fast: false`, each with its own artifact: the findings, the
  logs and the screenshots. A job that fails also keeps its result bundles for a week,
  with the crash reports of a test runner that exited in the middle of a test; at up
  to some 170 MB each, a job that passes does not.
- **Retries:** a failing test runs once more, and only that test: once the run of the
  whole selection is over, `scripts/a11y.sh` reads the failed tests from its result
  bundle and starts a second run of just those, in a new test runner. A failure that
  names no test, such as a runner that crashed between two tests, runs the whole
  selection once more. A test runner that crashes before the tests start gets a
  second start, also when it times out while preparing to run the tests. Before a run
  once more, the script prints each failure of the first run, the test and the start of
  its failure text, into the job log; the result bundles are kept only when a job
  fails, so a test that passed on its run once more leaves no other trace there.
- **Build, boot, test:** `scripts/a11y.sh` builds with `build-for-testing`, then starts
  the simulator, waits for `simctl bootstatus`, and runs the tests with
  `test-without-building`. It does not wait for the machine to settle: on the CI
  runners it never does (see the consequences).
- **A load log on request:** with `A11Y_LOAD_LOG=1`, the script writes how busy the
  machine is every 10 s, the load, the idle CPU and the free memory, with a mark at
  each step, into `<device> load.log`, and prints it at the end of each device.
- **A warm-up first:** before the selection, `WarmUpTests` starts the app once and
  closes it, and once more if that fails; no selection includes it. Most launch
  failures came at the first launch of a job, where they failed the first test of the
  selection, a part of the audit among them.
- **One simulator at a time:** a simulator the script started is shut down once its
  device is done.

## Consequences

- **A failed audit costs one part:** a test that fails, such as one whose first app
  launch fails on a freshly booted simulator, or whose test runner exits in the middle,
  runs once more alone. With one test per text size, that was the whole audit of that
  size, 10 to 22 minutes; a part takes about half. Of the restarts in the logs so far,
  most followed a failed test, which Xcode does by itself; the few runners that exited
  in the middle of a test all did so in the long audit of the default text size.
- **Four more jobs:** the two parts of the audit run side by side, so a run ends
  sooner, but each job builds the app once more, a few minutes of runner time each.

- **Faster and steadier:** a run takes as long as its slowest job, about the audit on
  one device, rather than the sum of all.
- **Retries cost only what failed:** with `-retry-tests-on-failure -test-iterations 2`,
  as before, Xcode 27.1 ran the whole selection a second time after one failure. On
  CI that happened in about half of the iPhone and iPad jobs and in most of the iPhone
  Duo's, and cost 10–17 minutes each time.
- **The simulator starts after the build, and the machine stays busy:** a new
  simulator keeps the machine busy after it reports its start. Booted beside the build,
  it made the build take 6–19 minutes rather than about 1.5. On a Mac with 8 cores the
  CPU was fully busy for about 2.5 minutes after the boot and then mostly idle. On the CI
  runners, with 3 cores, the load log of all nine simulator jobs of one run showed no
  idle CPU from the boot to the end of the job, 20–45 minutes, at a mean load of
  300–750; free memory stayed at 30–60 %. A wait for a settled machine, tried for five
  minutes per job, therefore bought nothing there. What keeps the jobs green on such a
  machine is the warm-up, the second start of a test runner, the run once more of the
  tests that failed, and timeouts long enough for a busy machine.
- **Billing:** eight macOS jobs per pull request that changes more than documentation
  ([ADR-0078](0078-ci-skips-builds-for-docs.md)). On a runner that is billed per
  minute, this costs about as many minutes as before, plus a build per job.
- **Folding:** the iPhone Duo runs folded, as it boots; unfolding cannot be scripted.
- **The Mac in CI:** `make a11y-mac` is still there for a run on the maintainer's
  Mac, but a pull request no longer needs one.
- **Required check:** once the functional jobs pass steadily, they should become
  required ([ADR-0016](0016-branch-protection.md)). That is the maintainer's decision.
