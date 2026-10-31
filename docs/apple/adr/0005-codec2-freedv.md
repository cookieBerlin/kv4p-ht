# ADR-0005: Codec2 for FreeDV 2400B

- **Status:** Proposed
- **Date:** 2026-10-31

## Context

In FreeDV 2400B mode the modem runs on the ESP32; the host encodes and decodes
7-byte **Codec2 1300** frames (`HOST_TX_DIGITAL` / `RX_DIGITAL`). Android uses the
JNI wrapper `codec2-android`. Codec2 is a C library (LGPL-2.1, compatible with
this project's GPL-3.0).

## Considered options

1. **Build Codec2 from C sources as a SwiftPM C target / XCFramework** for macOS
   (arm64) and iOS/iPadOS (device + simulator slices).
2. **Port Codec2 to Swift** — large effort, high risk of subtle differences.
3. **Drop FreeDV on Apple** — loses a firmware feature.

## Decision

Option 1. A `KV4PDigital` package wraps the C library behind a small Swift API
(`encode(pcm) -> [UInt8]`, `decode([UInt8]) -> pcm`). Only the Codec2 1300 mode
and its dependencies are compiled.

## Consequences

- C sources are vendored or pulled via SwiftPM at a pinned version; the license
  notice is added to `other-licenses.txt` handling for the Apple app.
- The C code itself is excluded from Swift coverage; the Swift wrapper is
  covered 100 % and verified against reference vectors.
- FreeDV is the last feature of phase 1 ([04-roadmap.md](../04-roadmap.md)).
