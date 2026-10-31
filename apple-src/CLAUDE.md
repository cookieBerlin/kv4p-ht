# CLAUDE.md — Apple app

Applies in addition to the root [`CLAUDE.md`](../CLAUDE.md).

> Status: planning. The structure below is the target layout defined in
> [`docs/apple/02-architecture.md`](../docs/apple/02-architecture.md); it is
> created incrementally.

## Platforms

- macOS 26+ on Apple Silicon (phase 1), iOS 26+ and iPadOS 26+ (phase 2).
- One native SwiftUI multiplatform app, no Mac Catalyst
  ([ADR-0012](../docs/apple/adr/0012-platform-strategy.md)).
- Bundle identifier `io.github.cookieberlin.kv4pht`, defined only in
  `Config/Base.xcconfig` and overridable there.

## Layout

```
apple-src/
├── Packages/
│   ├── KV4PProtocol/    # KISS framing, KV4P vendor frames, HELLO/DeviceState codecs
│   ├── KV4PTransport/   # Transport abstraction; BLE (CoreBluetooth) + USB serial (macOS) adapters
│   ├── KV4PAudio/       # IMA ADPCM, resampling, audio pipeline, AVAudioEngine adapter
│   ├── KV4PDigital/     # Codec2 / FreeDV wrapper (C library)
│   ├── KV4PAPRS/        # AX.25 / APRS encode + decode
│   ├── KV4PRadio/       # Radio controller, state machine, use cases, view models
│   ├── KV4PPersistence/ # Memories, settings, APRS history
│   ├── KV4PFlasher/     # ESP32 ROM bootloader flashing (macOS only)
│   └── KV4PSimulator/   # In-process radio simulator + scenarios
├── App/                 # Thin SwiftUI app target (macOS, iOS, iPadOS)
├── SimulatorPeripheral/ # macOS app: BLE peripheral simulating a kv4p HT
├── Config/              # xcconfig files
└── Makefile             # single entry point, used locally and in CI
```

## Commands

All commands run natively on the Mac — no iOS simulator required for tests.

```bash
make test       # swift test for all packages
make coverage   # tests + coverage report + 100 % gate
make lint       # SwiftLint + SwiftFormat --lint
make vectors    # regenerate golden test vectors from the Android code (tools/test-vectors)
make ci         # everything CI runs, in the same order
```

CI calls `make ci`; never duplicate command lines in workflow files.

## Conventions

- Swift 6 language mode, strict concurrency.
- Hardware and OS APIs (CoreBluetooth, AVAudioEngine, AVAudioSession, IOKit serial)
  are only touched in thin adapters behind Swift protocols. Everything else is
  tested against fakes or the simulator.
- Platform differences use `#if os(macOS)` / `#if os(iOS)` only inside adapters.
- Protocol constants exist once, in `KV4PProtocol`. Other modules import them.
- Golden test vectors live in `Packages/*/Tests/**/Vectors/*.json` and are
  generated, never edited by hand.
- Test data uses placeholders only (`N0CALL`, `example.com`).

## Coverage exclusions

Defined in [ADR-0011](../docs/apple/adr/0011-coverage-policy.md). Only the thin
hardware adapters and the `@main` app entry point may be excluded, and each
exclusion is listed explicitly in the coverage configuration.
