# CLAUDE.md — Apple app

Applies in addition to the root [`CLAUDE.md`](../CLAUDE.md).

> Status: milestone 2.4 (iOS firmware notice). The structure below is the target layout
> defined in [`docs/apple/02-architecture.md`](../docs/apple/02-architecture.md);
> it is created incrementally.

## Platforms

- macOS 26+ on Apple Silicon (phase 1), iOS 26+ and iPadOS 26+ (phase 2).
- One native SwiftUI multiplatform app, no Mac Catalyst
  ([ADR-0012](../docs/apple/adr/0012-platform-strategy.md)).
- Bundle identifier `io.github.cookieberlin.kv4pht`, defined only in
  `Config/Base.xcconfig` and overridable there.

## Layout

One SwiftPM package (`Package.swift`) with one target per module
([ADR-0015](../docs/apple/adr/0015-build-layout-and-tooling.md)); targets are
added when their milestone starts.

```
apple-src/
├── Package.swift
├── Packages/
│   ├── KV4PProtocol/    # KISS framing, KV4P vendor frames, HELLO/DeviceState codecs
│   ├── KV4PTransport/   # Transport abstraction; BLE (CoreBluetooth) + USB serial (macOS) adapters
│   ├── KV4PAudio/       # IMA ADPCM, resampling, audio pipeline, AVAudioEngine adapter
│   ├── KV4PDigital/     # FreeDV voice; CCodec2: Codec2 1.2.0 vendored by tools/codec2-vectors
│   ├── KV4PAPRS/        # AX.25 / APRS encode + decode
│   ├── KV4PRadio/       # Radio controller, state machine, use cases, view models
│   ├── KV4PPersistence/ # Memories, settings, APRS history
│   ├── KV4PFlasher/     # ESP32 ROM bootloader flashing (macOS only)
│   ├── KV4PSimulator/   # In-process radio simulator + scenarios, SimulatorTransport, SimulatorPeripheral
│   ├── KV4PSimulatorPeripheral/ # kv4p-sim-peripheral: simulated kv4p HT over real BLE (macOS)
│   ├── KV4PTestSupport/ # Test doubles shared by test targets (ManualClock); not shipped
│   └── KV4PProbe/       # kv4p-probe: prints the HELLO of real hardware (macOS dev tool)
├── App/                 # KV4PHT.xcodeproj + thin SwiftUI app target (ADR-0019)
├── Config/              # xcconfig files
├── scripts/             # coverage gate, privacy check, change detection
├── apple-paths.txt      # Apple port paths (CI change detection, privacy check)
├── coverage-exclusions.txt
├── privacy-exclusions.txt   # vendored third-party code the privacy check skips
└── Makefile             # single entry point, used locally and in CI
```

## Commands

All commands run natively on the Mac — no iOS simulator required for tests.

```bash
make test       # swift test for all modules
make coverage   # tests + coverage report + 100 % gate
make lint       # swift format lint --strict
make format     # swift format --in-place
make privacy    # personal data check (files + commit e-mails), BASE=<ref> optional
make changed    # print true/false: does BASE...HEAD_REF touch an Apple path?
make ios-build  # compile all modules for iOS (no simulator)
make app        # build the app for macOS and iOS, check the iOS bundle, release dry run
make release    # signed, notarized macOS DMG; needs TEAM_ID and NOTARY_PROFILE (SIGN_IDENTITY=- for a dry run)
make icon       # render the app icon from ../artwork/app-icon.svg (commit the result)
make ci         # everything CI runs, in the same order
make vectors    # regenerate golden test vectors (Android code, vendored Codec2)
make vectors-check # make vectors, then fail if the committed vectors or Codec2 sources differ
swift run kv4p-probe [--ble | --serial [<device>] [--reset] | --list] [--tune <MHz>] [--listen <s>]  # hardware check
swift run kv4p-probe --flash <directory> [<device>]  # flash bootloader/partitions/boot_app0/firmware.bin over USB
swift run kv4p-sim-peripheral [--uhf] [--no-radio-module] [--signal] [--verbose]  # simulated radio over BLE
```

Requires Xcode (with `swift format`) and `jq`; `make vectors` also needs JDK 17
(`brew install openjdk@17`, or set `JAVA17_HOME`). Gradle 9 does not run on newer JDKs.

CI calls `make ci`; never duplicate command lines in workflow files.

## Conventions

- Swift 6 language mode, strict concurrency.
- Hardware and OS APIs (CoreBluetooth, AVAudioEngine, AVAudioSession, IOKit serial)
  are only touched in thin adapters behind Swift protocols. Everything else is
  tested against fakes or the simulator.
- Platform differences use `#if os(macOS)` / `#if os(iOS)` only inside adapters.
- Protocol constants exist once, in `KV4PProtocol`. Other modules import them.
- Golden test vectors live in `Packages/*/Tests/*/Vectors/*.json` and are
  generated, never edited by hand.
- Test data uses placeholders only (`N0CALL`, `example.com`).

## Coverage exclusions

Defined in [ADR-0011](../docs/apple/adr/0011-coverage-policy.md). Only the thin
hardware adapters and the `@main` app entry point may be excluded, and each
exclusion is listed explicitly in the coverage configuration.
