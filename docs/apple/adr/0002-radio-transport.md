# ADR-0002: Radio transport

- **Status:** Proposed
- **Date:** 2026-10-31

## Context

The firmware offers the same KISS byte stream over USB serial, Bluetooth Classic
SPP and a BLE GATT service ([03-protocol-spec.md §1](../03-protocol-spec.md)).
iOS and iPadOS do not allow generic USB serial devices without MFi certification
and provide no SPP API. macOS supports all three.

## Considered options

1. **BLE only** — works on all Apple platforms, no licensing; macOS users without
   BLE-capable firmware cannot connect.
2. **BLE everywhere + USB serial on macOS** — same app code above a transport
   protocol; USB gives macOS a wired, low-latency fallback and enables flashing.
3. **MFi USB accessory** — requires paid certification and hardware changes.
4. **Wi-Fi** — not supported by the firmware.

## Decision

Option 2. A `RadioTransport` protocol abstracts byte-stream I/O. Implementations:
`BLETransport` (all platforms) and `SerialTransport` (macOS only, `#if os(macOS)`).
SPP on macOS is not planned; it can be added later behind the same protocol.

## Consequences

- One protocol stack above the transport; the simulator plugs in as a third
  implementation ([ADR-0014](0014-radio-simulator.md)).
- macOS gets a wired path for development and firmware flashing.
- BLE throughput must be validated early (audio ≈ 8.2 kB/s per direction).
