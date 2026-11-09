# ADR-0062: Accessibility audit

- **Status:** Proposed
- **Date:** 2026-11-06

## Context

Milestone 3.7 asks that Apple's accessibility audit passes on every screen on iPhone, iPad and Mac, and that it runs
repeatably through the `Makefile`. The audit, `performAccessibilityAudit`, exists only in UI tests, which need a target
of their own in the Xcode project and an app in a known state. Manual VoiceOver tests are not planned. 3.7 has three
parts: making the audit run (3.7a), fixing what it finds on iPhone and iPad (3.7b), and the Mac with the exceptions
(3.7c).

## Decision

- **A UI test target, `KV4PHTUITests`,** with settings of its own in `Config/UITests.xcconfig`, as the project-wide
  `Base.xcconfig` is for the app: bundle identifier, Info.plist and entitlements. The project file only names it.
- **A demo mode, started with `-uitest-demo`:** the simulator, memories and packets only in memory, settings of their
  own that start anew, no iCloud, no notifications and no permission asked, so that no system question stops a test.
  It fills the app with placeholders: memories, a packet of each kind and two chats, one of them unread.
- **One test goes through every screen,** with the default and the largest text size (AX5), and runs the audit on each:
  memories, packets, chats, a chat, the settings and each of their pages. With the largest text it scrolls to the lower
  pages of the settings.
- **`make a11y` runs it on an iPhone and an iPad simulator** and writes the findings to `.build/a11y/findings.txt`. It is
  not part of `make ci`, as it needs the simulator; CI runs it as a job of its own and keeps the findings.
- **Until 3.7b, findings do not fail the test,** only a run that cannot go through the screens. Then the audit becomes
  strict, and each exception is named here with its reason.
- **The Mac follows in 3.7c,** as there the test runner must be signed and the user allows it to control the app once.

## Consequences

- A run takes about ten minutes for both simulators.
- The audit only finds what a machine can see; a screen it does not reach is not checked.
