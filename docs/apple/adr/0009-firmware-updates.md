# ADR-0009: Firmware updates

- **Status:** Accepted
- **Date:** 2026-10-31

## Context

The Android app flashes the ESP32 over USB (`esp32-flash-lib`) and warns when
the firmware is older than its packaged version (`PACKAGED_FIRMWARE_VER = 17`).
It writes four regions: bootloader, partition table, `boot_app0` and the app
image, taken from `android-src/KV4PHT/app/src/main/res/raw/`.
iOS/iPadOS cannot access the USB serial device. The firmware has no OTA update
path over BLE. Firmware code must not be modified for the Apple port.

## Considered options

1. **External flashing** — the app detects outdated firmware via `HELLO.ver` and
   links to the web flasher (website `firmware.html`) and the manual.
2. **USB flashing on macOS** — implement the ESP32 ROM bootloader protocol in
   Swift for macOS; iOS/iPadOS fall back to option 1.
3. **OTA over BLE** — requires firmware changes, out of scope.

## Decision

Option 2.

- **macOS:** a new package `KV4PFlasher` implements the ESP32 serial ROM
  bootloader protocol (reset into bootloader via DTR/RTS, SLIP framing, SYNC,
  baud rate change, `FLASH_BEGIN`/`FLASH_DATA`/`FLASH_END`, MD5 verification) on top
  of the macOS `SerialTransport` ([ADR-0002](0002-radio-transport.md)).
- **iOS/iPadOS:** outdated firmware shows a notice with a link to the web flasher
  and the manual.
- **Firmware images are not duplicated.** The build copies the four binaries from
  `android-src/KV4PHT/app/src/main/res/raw/` into the macOS app bundle; the
  packaged firmware version is read from the same source
  (`FirmwareUtils.PACKAGED_FIRMWARE_VER`) by the build script and defined once in
  `KV4PProtocol`.
- **Tests:** the bootloader protocol is developed test-first against a fake ROM
  bootloader in `KV4PSimulator`; SLIP/command byte vectors are generated from
  `esp32-flash-lib` in `tools/test-vectors/` ([ADR-0004](0004-android-code-reuse.md)).
  The DTR/RTS line control is part of the thin serial adapter
  ([ADR-0011](0011-coverage-policy.md)).

## Consequences

- macOS users can update the radio without other tools; flash region offsets and
  the image set follow the Android app automatically.
- Flashing is a risky operation: the UI requires explicit confirmation, keeps the
  Mac awake and verifies every region; a failed flash can be retried because the
  ROM bootloader is always available.
- iOS/iPadOS users still need a desktop browser, Android or a Mac to update.
