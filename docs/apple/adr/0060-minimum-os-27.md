# ADR-0060: Minimum OS 27

- **Status:** Proposed
- **Date:** 2026-11-05

## Context

[ADR-0008](0008-minimum-os-versions.md) chose version 26. Crash data for 4.8 comes from MetricKit, whose
`MXMetricManager` is marked as to be deprecated. Its successor `MetricManager` exists from version 27.
The app should not take on frameworks that are on their way out, and it is only on TestFlight so far, so
few people are affected.

## Decision

macOS, iOS and iPadOS 27 are the minimum. Devices that cannot run 27 are no longer supported.

Newly deprecated calls are replaced as well, which the build now reports:

- `AVAudioEngine.connect(_:to:format:)` becomes `connectNode(_:to:format:)`, which can throw.
- `AVAudioNode.installTap(onBus:bufferSize:format:block:)` becomes the variant with an error. The SDK gives
  it no plain Swift name yet, so it is called as `__installTap`. Once a plain name comes, this one changes.
- `AVAudioSession.interruptionNotification` becomes two: `didBecomeInactiveNotification` for the start of an
  interruption, if the system ended the session and not the app itself, and
  `resumptionRecommendationNotification` for its end, with whether to resume.

## Consequences

- CI runs on GitHub's `xcode-27` image, as tests run on the Mac they are built for.
- No `#available` branches for APIs up to version 27.
- The audio adapters changed in how they connect and hear about interruptions, not in what the app does
  then, which only a real radio and a real phone call can confirm.
- Raising the minimum again requires a new ADR.
