# ADR-0073: The start of the app – measured, quick, and with a launch screen of its own

- **Status:** Proposed
- **Date:** 2026-11-13

## Context

On an iPhone, the app showed a black screen at its start, for a time long enough to wonder whether it had crashed.
Two things made that screen:

- **The launch screen was empty.** Xcode generated it (`UILaunchScreen_Generation`): the system background, black
  in dark mode.
- **The first frame came late.** Nothing measured why.

## Considered options

1. **Text such as "Starting system…" on the launch screen.** The launch screen is a still image that the system
   shows before any code of the app runs, so such a text could not tell what is going on. Apple's guidelines advise
   against text there. Rejected.
2. **Measure the start, remove what holds up the first frame, and give the launch screen the look of the app.**
   Chosen.

## Decision

- **Measuring:** each part of the start is a signpost interval for Instruments (App Launch, points of interest). Once
  the first frame shows, the log gets one line ("Launch: first frame after … ms; …") with the time since the process
  started, what came before the app's code, each part of the composition, and what followed until the first frame.
  `LaunchTimes` in `KV4PDiagnostics` builds the line; `LaunchTrace` in the app measures.
- **The map is built once it is near.** On a phone, every page was built at the start, the map with MapKit too. In
  the simulator, a cold start took 3.8 s to its first frame with the map and 0.8–1.1 s without it. The map is built
  when its page shows or is a swipe away, and then stays. The side pane of a wide window builds it only when it is
  chosen, as before.
- **Launch screen:** the colour of the app icon (`LaunchBackground`: cream, and the icon's near-black in dark mode)
  with the radio of the icon in the middle, faint (`LaunchLogo`). `make icon` renders it from `artwork/app-icon.svg`,
  as it does the icon. There is one image for both appearances, a grey between the two colours at 25 % opacity,
  which reads as a slightly darker shade on cream and a slightly lighter one on near-black. The app's own code needs
  some tens of milliseconds and loads the memories after the first frame; they are not worth a loading text.

## Consequences

- **Device numbers:** the simulator and a Debug build show where the time goes, not how long it takes on a phone.
  The log line on a device tells that, also from TestFlight users through a problem report.
- **Simulator:** it keeps the launch screen across an uninstall, per appearance; a changed launch screen shows on a
  simulator that never ran the app.
- **Check:** `app-plist-check.sh` fails a build whose launch screen lacks the image or the colour, as an upload
  without a launch screen is refused (ITMS-90870).
