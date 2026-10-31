# ADR-0011: Test coverage policy

- **Status:** Accepted
- **Date:** 2026-10-31

## Context

The project requires test-driven development and 100 % coverage. Some code can
only execute against real hardware or the OS: CoreBluetooth delegate callbacks,
AVAudioEngine/AVAudioSession I/O, IOKit serial ports, and the `@main` app entry
point. Requiring coverage there would force hardware in CI or meaningless tests.

## Considered options

1. **100 % everywhere** — not achievable in CI without hardware.
2. **Threshold below 100 % (e.g. 90 %)** — hides gaps in logic code.
3. **100 % for all packages, with an explicit, minimal exclusion list for thin
   hardware adapters** — logic is fully covered, exclusions are visible and reviewed.

## Decision

Option 3.

- **Metric:** line coverage from `swift test --enable-code-coverage` (llvm-cov),
  gate at **100.00 %** of all non-excluded files. Region coverage is reported.
- **Allowed exclusions** (listed file by file in `apple-src/coverage-exclusions.txt`):
  - hardware adapters that only forward between an OS API and a Swift protocol
    (e.g. `CoreBluetoothCentral.swift`, `AVAudioEngineIO.swift`, `IOKitSerialPort.swift`);
  - the app entry point (`@main`) and SwiftUI `View` bodies without logic;
  - vendored C code (Codec2).
- An adapter may only be excluded if it contains **no branching logic** beyond
  forwarding; any logic is moved into a covered type.
- Excluded adapters are exercised by manual hardware test checklists and by the
  BLE peripheral simulator ([ADR-0014](0014-radio-simulator.md)).
- Adding an exclusion requires a pull request that explains why.

## Consequences

- CI fails on any uncovered line outside the exclusion list.
- Architecture is pushed towards thin adapters and protocol-based design.
- View models carry all UI logic and are fully covered.
