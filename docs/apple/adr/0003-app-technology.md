# ADR-0003: App technology

- **Status:** Accepted
- **Date:** 2026-10-31

## Context

The app targets macOS, iOS and iPadOS. It needs low-latency audio
(AVAudioEngine), CoreBluetooth, background modes on iOS and a native look on
Mac and iPad. The Android code must not be modified
([root CLAUDE.md](../../../CLAUDE.md)), which rules out refactoring it into a
shared module.

## Considered options

1. **Native Swift + SwiftUI multiplatform** — first-class access to all Apple
   APIs, one code base for the three platforms, `swift test` runs natively on the Mac.
2. **Kotlin Multiplatform** — could share logic with Android, but only after
   restructuring the Android code, which is out of bounds; audio/BLE would still
   be native per platform.
3. **Flutter / React Native** — another runtime and plugin layer between the app
   and the latency-critical audio/BLE paths; no reuse of the Java code either.

## Decision

Option 1: Swift 6 (strict concurrency) and SwiftUI, with all logic in Swift
packages.

## Consequences

- No code sharing with Android; compatibility is ensured by golden test vectors
  ([ADR-0004](0004-android-code-reuse.md)).
- Contributors need Swift/SwiftUI skills.
