# ADR-0059: Logging and problem reports

- **Status:** Proposed
- **Date:** 2026-11-05

## Context

Apart from the audio adapters, the app logged nothing, and errors could go unnoticed: a store that did not
open looked like an empty one. On iPhone and iPad the system's log only reaches back to the start of the
running process, so it cannot explain a crash afterwards. Reports must reach the maintainer without a
server, and without a personal address in the app or the repository.

## Decision

- **The log goes to the system console and to files on the device.** Files are named by their day, 1 MB
  each, at most 8, for 7 days, not synced and out of backups. Their age comes from the name, so the app
  reads no file dates, for which Apple asks a reason.
- **It always runs, and can be deleted.** *Detailed logging*, off by default, also logs each packet by its
  kind, and ends by itself after a day.
- **What goes in:** connections and their status, the firmware and module, the start and end of a
  transmission, audio session events, refused permissions, sync, firmware updates, what the user is told,
  and errors of the stores.
- **What never goes in:** message texts, positions, callsigns, the APRS-IS password, names of memories and
  radios. An error is told by its domain and code, as its text can hold a path with the user's name. The
  real-time audio paths do not log.
- **Crash data comes from MetricKit's `MetricManager`** ([ADR-0060](0060-minimum-os-27.md)), one instance
  for the app. Up to 5 crashes stay, without the region of the device. TestFlight's own crash reports and
  feedback stay as they are. No third-party service.
- **After a new crash, the app asks once** whether to report it.
- **A report is made under *About*:** the user sees it, and shares the file through the system's dialog or
  opens a prepared GitHub issue, to which they attach it. The issue holds only versions and device, and says
  that issues are public. The callsign is replaced in the whole report, in any case and with any SSID.
  Nothing leaves the device without the user.

## Consequences

- When MetricKit delivers a crash is up to the system, and it does not deliver under a debugger, so this
  shows only in real use.
- The last lines before a crash can be missing, as they are written away from the caller.
- Before an App Store release (99.1), the privacy details have to name crash data sent by the user.
