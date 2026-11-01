# ADR-0032: iPhone and iPad layouts

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

The Mac window is a `NavigationSplitView`: memories in the sidebar, radio and APRS
as tabs in the detail column. On iOS it has these problems:

- On the iPhone the split view collapses to the memory list. Without memories,
  the radio cannot be reached.
- On the iPad the detail column does not show the toolbar buttons of its tabs.
- Several views have Mac widths: the radio form (`minWidth: 420`), the memory
  editor, the About and licence windows, and the APRS settings rows with fixed
  widths of 110–220 pt.
- PTT sits at the bottom of a long form. Android shows a large PTT button on
  its main screen.

## Decision

- **Main view on iOS:** iPhone and iPad use one `TabView` (`sidebarAdaptable`)
  with *Radio*, *Memories* and *APRS*. Each tab has its own `NavigationStack`, so
  its toolbar shows. The iPhone shows the tabs at the bottom; the iPad shows them
  at the top or as a sidebar, also in Split View and Slide Over. The last tab is
  remembered (`@AppStorage`). The Mac keeps the split view.
- **PTT bar (iOS):** on *Radio* and *Memories*, a bar at the bottom of the screen
  holds:
  - the frequency (or the status) and the S-meter;
  - a 64 pt PTT button with haptic feedback.

  It works like the Mac button: hold to transmit, or toggle with sticky PTT. The
  Mac keeps the button in *Transmit*.
- **About on iOS:** an ⓘ button in the radio tab opens it as a sheet.
- **APRS on iOS:** the station, beacon, digipeater and APRS-IS settings move into
  a sheet (⚙). The screen keeps the feed and a message line. Each control is
  defined once and placed by platform.
- **Memories on iOS:** iOS lists select only in edit mode, so a tap tunes and a
  checkmark marks the active memory. Swipe actions edit or delete, on all
  platforms.
- **Frequency field on iOS:** it uses the numbers keyboard with a *Done* key, so
  *Return* applies the frequency.
- **Mac widths:** they apply only on macOS.

## Consequences

- **iPad:** memories and the radio are no longer side by side. The PTT bar on the
  memory tab still allows tuning and talking without switching tabs.
- **Tests:** the layout lives in the app target, which has no unit tests
  ([ADR-0019](0019-xcode-app-project.md)); no model logic changed. It is checked
  with simulator screenshots and the hardware checklist.
