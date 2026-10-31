# ADR-0009: Firmware updates

- **Status:** Proposed
- **Date:** 2026-10-31

## Context

The Android app flashes the ESP32 over USB (`esp32-flash-lib`) and warns when
the firmware is older than its packaged version. iOS/iPadOS cannot access the
USB serial device. The firmware has no OTA update path over BLE. Firmware code
must not be modified for the Apple port.

## Considered options

1. **External flashing** — the app detects outdated firmware via `HELLO.ver` and
   links to the web flasher (website `firmware.html`) and the manual.
2. **USB flashing on macOS** — port the ESP32 ROM bootloader protocol (or embed
   esptool logic) for macOS.
3. **OTA over BLE** — requires firmware changes, out of scope.

## Decision

Option 1 for all platforms in phases 1 and 2. Option 2 is a candidate for a later
phase on macOS and would get its own ADR.

## Consequences

- No bootloader code in the app; smaller scope and risk.
- Users need a browser with Web Serial (desktop Chrome/Edge) or an Android/macOS
  tool to update firmware; documented in the manual and FAQ.
- The minimum supported firmware version is defined once in `KV4PProtocol`.
