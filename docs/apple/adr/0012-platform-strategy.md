# ADR-0012: Platform strategy

- **Status:** Accepted
- **Date:** 2026-10-31

## Context

Targets are macOS (Apple Silicon), iOS and iPadOS. Development happens on an
Apple Silicon Mac. Running tests and the app natively on the Mac is faster than
using the iOS simulator, and the Mac has real Bluetooth and USB for hardware tests.

## Considered options

1. **macOS first, then iOS/iPadOS, one native SwiftUI multiplatform target**.
2. **iOS first, Mac via Mac Catalyst** — Catalyst apps feel like iPad apps on the
   Mac and do not get full macOS APIs (e.g. IOKit serial).
3. **All platforms in parallel** — triples UI and adapter work from day one.

## Decision

Option 1.

- **Phase 1:** macOS app with all features; platform-neutral packages.
- **Phase 2:** iOS and iPadOS: AVAudioSession, background modes, compact and
  regular size class layouts, TestFlight.
- No Mac Catalyst. Platform-specific code only in adapters (`#if os(...)`).
- From phase 1 on, CI builds the packages for iOS as well (compile check only),
  so platform-specific API usage is caught early.

## Consequences

- Fast TDD loop on the Mac without simulators.
- iOS-specific risks (audio session, background BLE) are addressed in phase 2;
  the early iOS compile check reduces surprises.
