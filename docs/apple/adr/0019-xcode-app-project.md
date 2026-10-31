# ADR-0019: Xcode project for the app target

- **Status:** Accepted
- **Date:** 2026-11-01

## Context

All logic lives in the SwiftPM package `apple-src/Package.swift`
([ADR-0015](0015-build-layout-and-tooling.md)). The app itself needs what
SwiftPM does not provide: an `.app` bundle with `Info.plist` (the Bluetooth
usage description), App Sandbox entitlements (Bluetooth, USB serial), code
signing, and later an iOS/iPadOS target ([ADR-0012](0012-platform-strategy.md)).
The bundle identifier lives in `apple-src/Config/Base.xcconfig`
([ADR-0010](0010-repository-structure.md)). ADR-0015 rules out third-party build
tools such as XcodeGen or Tuist.

## Considered options

1. **Committed Xcode project** — one multiplatform SwiftUI app target that depends
   on the local package; standard bundling, signing and iOS support.
2. **SwiftPM executable plus a bundling script** — no project file, but bundle,
   entitlements and signing are rebuilt by hand, and iOS is not possible.

## Decision

Option 1.

- `apple-src/App/KV4PHT.xcodeproj` with one multiplatform target `KV4PHT`
  (macOS first, iOS/iPadOS in phase 2). It lives in `App/` so that `xcodebuild`
  in `apple-src/` keeps resolving the package.
- Sources are a synchronized folder (`App/KV4PHT/`), so adding files does not
  change the project file.
- Build settings come from `Config/*.xcconfig`, not from the project file.
- The target only contains the composition root and SwiftUI views without logic;
  view models live in `KV4PRadio` and are covered there
  ([ADR-0011](0011-coverage-policy.md)).
- `make app` builds the macOS app without signing; CI runs it.

## Consequences

- The project file is reviewed like code; it changes rarely thanks to the
  synchronized folder and xcconfig files.
- Building the app needs Xcode (already required for `swift format`).
- Signed and notarised builds are a later step.
