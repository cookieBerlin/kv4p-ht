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
  simulator; CI runs it as a job of its own, which is not required for a merge, and keeps the findings, the log of each
  simulator and the screenshots.
- **The audit is strict since 3.7b:** every finding fails the test, except those below. The test names the number of the
  exception for each finding it lets pass, so that the list here and the code stay in step. A busy simulator lets an
  audit run out of time now and then; it then runs one kind of check at a time, each up to five times, with a pause
  that grows from one attempt to the next. The check of Dynamic Type always runs on its own: together with the others
  it flags text that grows, such as all of a chat.
- **A screen with findings is checked twice:** after a pause of three seconds, the test runs every check on it once
  more, and only what both looks find counts. On a slow machine, such as CI's, the audit catches a screen before its
  text has grown, and flags it, but seldom twice the same text; a real finding is there both times. The log keeps the
  first look's findings as `A11Y-FIRST-LOOK` and those of the second look alone as `A11Y-ONCE`, which `make a11y` does
  not count. A finding whose element has gone since, such as a part of a map drawn anew, is passed over, as nothing
  is left to read; if it stays, the second look finds it.
- **The bars above and below the lists are opaque, and the lists end at them,** on every platform. Behind a
  translucent bar, a row that a list scrolled out of sight still showed through, too faint to read, and the audit
  flagged it; on the iPad with the largest text that happened on every run. The button to connect and disconnect uses
  the app's darker blue on iPhone and iPad, as the system's blue on the grey of the header fails the contrast check.
- **The Mac since 3.7c, with `make a11y-mac`:** the same test, run by hand only, as it takes over the mouse and the
  keyboard. Its own kinds of check stand in for Dynamic Type, clipped text and traits, which the Mac does not have: the
  actions of an element and the match of parent and child. It goes through the main window, the chats and a chat, each
  page of the settings window by its sidebar, and the About window. The test runner is signed ad hoc, without a team,
  and without the hardened runtime, which would not let it load the tests; it is built outside the checkout, as macOS
  asks each new build for access to a folder such as Documents. Screenshots show the app's window only, cut out of the
  screen, which shows whatever else is open; for the same reason the scheme keeps no attachments of its own, such as
  screen recordings, and the test fails on its findings at the end rather than through issues of XCTest, which would
  attach the whole screen. macOS opens the windows of the last run again; the test closes the About window first.

### Exceptions

1. **Contrast that nearly passes, and the grey text of the settings:** Apple's secondary grey for secondary text and the
   footers of forms. The app's own small text that must stay readable, in the header, the status and the times, uses a
   darker grey.
2. **Contrast that the screenshot shows to be enough:** the audit misreads the background now and then, above all on the
   iPad, and flags black text on white from one run to the next. For such a finding the test measures the element on the
   screenshot of the screen, its lightest against its darkest pixel, and lets it pass at 4.5:1 or more, with the value
   in the log. The element's frame may hold more than its text, so this is its best case; a light text on a light
   background still fails. A row that a list scrolls below a bar is covered and has nothing to read; the test knows it
   as it cannot be tapped, or as it sticks out of its list.
3. **Dynamic Type of the header, the page bar and PTT:** kept small on purpose. The header grows up to the second
   accessibility size, like an instrument whose frequency has a size of its own; the symbols of the page bar keep
   their size, and a long press shows them large instead; PTT has a limit of its own.
4. **Dynamic Type of text fields:** SwiftUI's text fields grow with the text on the screenshots; the audit does not see
   it.
5. **A disabled choice without the trait "not enabled":** SwiftUI's own; VoiceOver reads it as dimmed all the same.
6. **Dynamic Type and clipped text in SwiftUI's lists and forms:** their rows wrap on the screenshots rather than being
   cut. The same for clipped text in *What's New*: the audit flags entries of three lines and more, whose frames hold
   all their lines (ADR-0069).
7. **Findings without an element:** the audit names no element, so none can be matched or fixed; the screenshot of the
   screen is checked instead.
8. **Mac: the action "show menu" of a pop-up button:** SwiftUI's pickers offer "press" only, which opens their menu
   all the same. Menus of the app's own keep both: in a bordered style SwiftUI drops "show menu", so a menu in the look of
   a capsule is drawn around a plain one on the Mac.
9. **Mac: groups without a name as high as a window:** the containers SwiftUI puts around a window's content and its
   sidebar column, and around the content of a sheet, such as *What's New*.
10. **Mac: the knob of a slider:** a part of AppKit's own, without a name; the slider has it.
11. **Mac: contrast in a window behind the front one, or cut off at its edge:** macOS dims a window that is not in front,
    and the rest of a window behind a sheet open on it, such as About behind *What's New*.
12. **Mac: the header of a section in the list of groups of memories, or in the list of the map:** SwiftUI shows it
    as a group without a name and not as a child of its parent.
13. **The link *Legal* of the map:** MapKit puts its legal notice on every map, with a link smaller than a finger. It
    is Apple's and cannot be changed by the app ([ADR-0068](0068-map.md)).
14. **The mark of the band in a marker of the map:** MapKit draws the *2m*, *70* or dot of a marker in a size of its
    own, which does not grow with the text, and the audit counts it as clipped; the screenshot shows it whole. The
    marker's name, which VoiceOver reads, and the list grow with the text.
15. **Mac: the markers of the map:** MapKit draws them on the Mac as images and text without names, and the audit
    cannot read their contrast on the map. The list of the map has every marker with its name for VoiceOver.

## Consequences

- A run takes about ten minutes for each simulator, and about seven on the Mac. The simulators run one after the other and nothing else should
  run beside them: on a fully loaded machine the audit can catch a screen before its text has grown, and flag it. On
  CI's hosted runners a run of both takes 30 to 50 minutes.
- The audit only finds what a machine can see; a screen it does not reach is not checked.
- The exceptions are kept narrow, by kind of check, element and screen. A new screen or control that the audit flags
  fails the test, and needs a fix or a new exception here.
