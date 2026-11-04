# ADR-0040: Screen layout and control explanations

- **Status:** Proposed
- **Date:** 2026-11-03

## Context

The radio screen is one long form with every setting, and the frequency and S-meter
scroll out of view. The memories and APRS are separate views, and each platform
arranges them differently. Users who know the Android app do not find its structure.
Several controls do not say what they do.

## Decision

- **One structure, as in the Android app:** a header with the connection, frequency,
  band, squelch state and S-meter; the memories and APRS below; PTT always in reach;
  the settings on their own screen.
- **Apple controls:** the app takes over the structure, not the colours, the font or
  the animated receive circle. A reworked layout changes no behaviour: the user still
  connects by hand, unlike on Android, and chooses the radio as in ADR-0038.
- **Room decides, not the device:** with a regular width, and always on the Mac, the
  memories and APRS stand side by side. A compact width, which includes an iPad in a
  narrow window, shows the memories, APRS and the settings as pages to swipe between,
  with a bar of its own at the bottom, as the system tab bar cannot swipe.
- **PTT outside the pages:** the header and PTT do not move with a page. A moving
  finger on PTT therefore cannot change the page and end the transmission.
- **Settings:** the Mac uses its settings window (⌘,), and a wide iPad pushes a page.
  Sections
  that need a radio stay visible and say so, and the frequency limits are under
  *Advanced*. The RepeaterBook import moves here, as a phone has no room for it.
- **Memory actions:** each memory shows a button with its actions, because the pages
  take a sideways swipe and a touch and hold cannot be discovered.
- **S-meter colours:** yellow for S1 to S3, green for S4 to S9, orange above S9 and red
  for overload. Radios follow no common standard, but most show the range above S9
  differently. Red stays for the one real problem, as a strong signal is good. The value
  also shows as text, so the colours are not the only information.
- **Notices:** problems other than a failed connection show as a line at the bottom of
  every screen until dismissed, on a phone above the page bar. They were not visible at
  all before.
- **Permissions:** the first Connect asks for the microphone, the location and, on
  iPhone and iPad, notifications. A Bluetooth connection also asks for Bluetooth. The
  simulator asks for nothing. Before Bluetooth is decided, the app does not scan, as a
  scan would ask.
- **Without a permission:** the function goes away and says why, with a button to the
  system settings. The beacon switch is grey, and an active beacon ends and stays off.
  PTT is replaced by the text. Connect is grey for Bluetooth radios; USB and the
  simulator still work.
- **Status and messages at the bottom:** the status moves from the header to above PTT.
  A failed connection shows there once, in red with its reason. The Mac has a status bar
  at the bottom of the window instead, and the dialog of ADR-0039. A finished import is
  a green message.
- **PTT touch:** iPhone and iPad use a `UIControl`, as SwiftUI's gesture reported a held
  touch late. The Mac keeps the gesture.
- **PTT:** on a phone, only the memories page shows it, as it serves no purpose on the
  APRS page.
- **Volume:** in the header when there is room, otherwise in the settings.
- **Firmware:** an outdated firmware shows its notice at the bottom. The update also
  stays available in the settings.
- **Explanations (`ControlHelp`):** each text exists once. The Mac shows it as a
  tooltip. On iPhone and iPad, a setting has it below the row, and a control without
  room has an info button.

## Consequences

- The Bluetooth scan of ADR-0038 no longer depends on a radio screen. It runs while the
  app is active and nothing is connected, as the picker is always in the header. The list
  of radios stays empty until the first Bluetooth connection has settled the permission.
- The header takes room from the lists, more so on a phone in landscape.
- `SettingsView` holds what was on the radio screen and in the APRS settings, so the
  callsign field moves out of the APRS screen.
- The layout cannot be tested automatically before milestone 3.7; hardware test HW-19
  covers it.
