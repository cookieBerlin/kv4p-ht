# ADR-0036: No distribution outside the App Store

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

[ADR-0034](0034-macos-release.md) planned a signed and notarized DMG for the Mac.
With TestFlight on all platforms ([ADR-0035](0035-testflight.md)), that DMG would
be a second way to distribute the app. It needs its own certificate, notary
profile, script and CI step, and its releases must be published by hand. The
maintainer wants to avoid that effort.

## Decision

- The app reaches users through App Store Connect only: TestFlight now, the App
  Store later (milestone 2.6). This applies to macOS as well.
- The DMG, `make release` and `scripts/release-macos.sh` are removed. This
  supersedes ADR-0034.
- Building from source with Xcode stays possible.

## Consequences

- One release path for all platforms, and no Developer ID certificate or notary
  profile to maintain.
- Until the App Store release, the Mac app is available only to invited testers,
  and TestFlight builds expire after 90 days.
- Every public version goes through App Review. App Review may object to the
  firmware flasher of the Mac app. If it does, the Mac app would point to the web
  flasher, as the iOS app does ([ADR-0009](0009-firmware-updates.md)).
- The app stays sandboxed, as the Mac App Store requires.
