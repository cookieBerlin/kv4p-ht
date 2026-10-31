# 05 — Testing Strategy

Status: draft. Policy: [ADR-0011](adr/0011-coverage-policy.md) ·
CI: [ADR-0013](adr/0013-ci-pr-gate.md) · Simulator: [ADR-0014](adr/0014-radio-simulator.md)

## Principles

1. **TDD** — Red → Green → Refactor for every change. A pull request without tests
   for new behaviour is incomplete.
2. **100 % line coverage** of all Swift packages, minus the explicit exclusion
   list of thin hardware adapters.
3. **No hardware, no simulator app needed for the test suite** — `swift test`
   runs natively on the Mac and in CI.
4. **One source of truth** — byte-level expectations come from golden vectors
   generated from the Android code, not from hand-written duplicates.

## Test pyramid

| Level | Scope | Tools | Runs in CI |
|---|---|---|---|
| Unit | pure types: codecs, parsers, state machines, view models | Swift Testing (`@Test`) | yes |
| Vector | Swift implementation vs. golden JSON vectors | Swift Testing, parameterised | yes |
| Integration | `RadioController` + protocol + audio pipeline against `KV4PSimulator` (A) with scenarios (C) | Swift Testing | yes |
| BLE integration | real `BLETransport` against `SimulatorPeripheral` (B) | manual / local script | no (needs two BLE endpoints) |
| Hardware | real kv4p HT over BLE and USB | manual checklist per milestone | no |
| UI | view models fully; views via previews and optional snapshot tests | Swift Testing | yes |

## Golden test vectors

- Generator: `tools/test-vectors/` (Gradle, JDK 17), compiles the original files
  from `android-src/` by path, with stubs for `android.util.Log` and
  `androidx.annotation.NonNull` ([ADR-0004](adr/0004-android-code-reuse.md)).
- Output: JSON files under `apple-src/Packages/<Package>/Tests/<Target>/Vectors/`.
  Each vector has `name`, `input`, `expected` and the generator source.
- Coverage of vectors:
  - KISS encode/decode, escaping, garbage before `FEND`, empty frames, unknown
    escapes, oversize frames.
  - Vendor frames for every command; wrong prefix/version.
  - `HostDesiredState`, `DeviceState`, `Hello`, `WindowUpdate` round-trips.
  - IMA ADPCM block encode/decode (tones, noise, silence, clipping).
  - S-meter values across the full RSSI range.
  - AX.25 / APRS packets.
- Additional cases are taken from the firmware native tests in
  `microcontroller-src/test/` where applicable.
- The included Android sources are listed once in
  `tools/test-vectors/oracle-sources.txt`.
- `make vectors` regenerates (JDK 17); `make vectors-check` fails if the output
  differs from the committed files. The CI `vectors` job runs it whenever Apple
  paths or the listed Android sources change, so upstream changes to the Android
  reference code surface as a failing check.

## Fakes and simulator

- Every OS-facing protocol (`RadioTransport`, `AudioIO`, `LocationProvider`,
  `Clock`, `NetworkConnection`) has an in-memory fake in a shared test-support target.
- Time is injected (`Clock` protocol) so timeouts, status-report intervals and the
  TX watchdog are tested without sleeping.
- `KV4PSimulator` provides end-to-end behaviour; scenarios cover firmware
  versions, module types, feature flags and faults. `RadioSimulator` is a value
  type driven by explicit time (`receive(_:at:)`, `advance(to:)`), so status
  reports and watchdogs are tested without a clock. Its tests read the output
  with the Android-verified `KISSParser`.

## Coverage measurement

- `make coverage` runs `swift test --enable-code-coverage`, exports llvm-cov JSON
  from the merged profile of **all** test bundles (`swift test
  --show-codecov-path` covers only the first one), removes files listed in
  `apple-src/coverage-exclusions.txt`, and fails if line coverage is below
  100.00 % or a module has no coverage data. The same script runs in CI.
- The coverage report is uploaded as a CI artifact.

## Hardware test checklist (per milestone)

Kept in [manual.md](manual.md#hardware-test-checklist); includes:
connect via BLE and USB, HELLO/version shown, RX audio continuous for 10 minutes,
PTT into a dummy load, reconnect after power cycle, out-of-range frequency rejected.

## Privacy in tests

Test data only uses placeholders (`N0CALL`, `N0CALL-9`, `example.com`, coordinates
of public reference points rounded to 2 decimals). The CI privacy job enforces
this ([ADR-0013](adr/0013-ci-pr-gate.md)).
