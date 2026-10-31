# ADR-0008: Minimum OS versions

- **Status:** Accepted
- **Date:** 2026-10-31

## Context

The project starts from scratch. Supporting older OS versions costs
availability checks and test effort; the current toolchain is Xcode 27 /
Swift 6.4.

## Considered options

1. **macOS / iOS / iPadOS 26** — one release back from current, broad device
   coverage, all modern SwiftUI, SwiftData and Observation APIs available.
2. **Version 27 only** — fewer users, little gain.
3. **Older (e.g. 17 / macOS 14)** — more users, many availability branches.

## Decision

Option 1: macOS 26 (Apple Silicon only), iOS 26, iPadOS 26.

## Consequences

- No `#available` branches for APIs introduced up to version 26.
- Intel Macs are not supported.
- Raising the minimum later requires a new ADR.
