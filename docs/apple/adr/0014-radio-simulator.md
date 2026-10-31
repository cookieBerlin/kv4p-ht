# ADR-0014: Radio simulator

- **Status:** Accepted
- **Date:** 2026-10-31

## Context

Real hardware is available, but TDD and CI need a radio that is deterministic,
fast and always available. Hardware also cannot easily reproduce failure modes
(disconnects mid-frame, wrong firmware version, lost notifications).

## Considered options

- **A. In-process simulator** — Swift implementation of the device side of the
  protocol, exposed as a `RadioTransport`.
- **B. BLE peripheral simulator** — macOS app using `CBPeripheralManager` that
  advertises the kv4p GATT service, so the real `BLETransport` can be tested
  without hardware.
- **C. Scenarios** — scripted behaviour and fault injection for A and B.

## Decision

All three.

- **A — `KV4PSimulator` package.** Implements the device state machine
  (HELLO after connect, desired-state handling with `appliedSequence`, status
  reports, flow-control window updates, TX watchdog), generates RX audio (tones,
  noise, recorded samples as ADPCM), echoes TX, emits AX.25 packets. It reuses
  `KV4PProtocol` and `KV4PAudio` for encoding — no duplicated protocol knowledge.
- **B — `SimulatorPeripheral` macOS app.** Thin `CBPeripheralManager` adapter that
  bridges the GATT characteristics to the same simulator core from A. It can run
  on a second Mac or alongside the app (two processes).
- **C — Scenarios** are data (Swift values or JSON) used by A and B: firmware
  version, RF module type, frequency limits, feature flags, packet scripts,
  faults (disconnect, garbage bytes, unknown escapes, oversize frames, dropped
  window updates, delayed state application).

The simulator core is verified against the same golden vectors as the app, so it
cannot drift from the real protocol.

## Consequences

- Integration tests run in CI against A; B is used for local BLE testing.
- The app can be demoed without hardware (simulator transport selectable in a
  debug menu).
- The simulator core is production-quality code and covered 100 %.
