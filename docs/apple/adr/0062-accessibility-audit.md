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
  memories, packets, chats, a chat, the settings and each of their pages. It scrolls the settings until each link is on
  screen, and a page it does not reach counts as a finding.
- **`make a11y` runs it on an iPhone and an iPad simulator** and writes the findings, each with its device, to
  `.build/a11y/findings.txt`, and a screenshot of each screen next to them. It is not part of `make ci`, as it needs the
  simulator; CI runs it as a job of its own and keeps the findings.
- **The audit is strict since 3.7b:** every finding fails the test, except those below. The test names the number of the
  exception for each finding it lets pass, so that the list here and the code stay in step. A busy simulator lets an
  audit run out of time now and then; it then runs one kind of check at a time, each up to three times. The check of
  Dynamic Type always runs on its own: together with the others it flags text that grows, such as all of a chat.
- **The Mac follows in 3.7c,** as there the test runner must be signed and the user allows it to control the app once.

### Exceptions

1. **Contrast that nearly passes, and the grey text of the settings:** Apple's secondary grey for secondary text and the
   footers of forms. The app's own small text that must stay readable, in the header, the status and the times, uses a
   darker grey.
2. **Contrast that the screenshot shows to be enough:** the audit misreads the background now and then, above all on the
   iPad, and flags black text on white from one run to the next. For such a finding the test measures the element on the
   screenshot of the screen, its lightest against its darkest pixel, and lets it pass at 4.5:1 or more, with the value
   in the log. The element's frame may hold more than its text, so this is its best case; a light text on a light
   background still fails. A row that a list scrolls below a bar is covered and has nothing to read; the test knows it
   as it cannot be tapped.
3. **Dynamic Type of the header, the page bar and PTT:** kept small on purpose. The header grows up to the second
   accessibility size, like an instrument whose frequency has a size of its own; the symbols of the page bar keep
   their size, and a long press shows them large instead; PTT has a limit of its own.
4. **Dynamic Type of text fields:** SwiftUI's text fields grow with the text on the screenshots; the audit does not see
   it.
5. **A disabled choice without the trait "not enabled":** SwiftUI's own; VoiceOver reads it as dimmed all the same.
6. **Dynamic Type and clipped text in SwiftUI's lists and forms:** their rows wrap on the screenshots rather than being
   cut.
7. **Findings without an element:** the audit names no element, so none can be matched or fixed; the screenshot of the
   screen is checked instead.
- **The Mac follows in 3.7c,** as there the test runner must be signed and the user allows it to control the app once.

## Consequences

- A run takes about ten minutes for each simulator. The simulators run one after the other and nothing else should
  run beside them: on a fully loaded machine the audit can catch a screen before its text has grown, and flag it.
- The audit only finds what a machine can see; a screen it does not reach is not checked.
- The exceptions are kept narrow, by kind of check, element and screen. A new screen or control that the audit flags
  fails the test, and needs a fix or a new exception here.
