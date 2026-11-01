# ADR-0028: Firmware flashing as a port of FirmwareUtils

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

[ADR-0009](0009-firmware-updates.md) chose USB flashing on macOS through the ESP32
ROM bootloader. It also says the images come from `android-src` and the protocol is
pinned by vectors from `esp32-flash-lib`. It left open what exactly the vectors
record and how the app gets the images.

Android's `FirmwareUtils.flashFirmware` (esp32-flash-lib 1.1.17) runs this
sequence:

1. **Connect at 115200 baud:** reset into the bootloader with DTR/RTS, then SYNC
   (20 attempts, then pending answers are flushed).
2. **Switch to 921600 baud.**
3. **Detect the chip.**
4. **Load the esptool flasher stub** (`stubs/1/esp32.json`, GPL-2.0-or-later) and
   wait for its "OHAI".
5. **Write the regions:**
   - bootloader `0x1000`, partition table `0x8000` and `boot_app0` `0xE000`,
     uncompressed in 16 KiB blocks padded with zeros;
   - the app `0x10000`, zlib-compressed (`Deflater`, best compression).
6. **Verify each region by MD5 and reset.**

The progress callback weights each region by its size. The menu offers flashing at
any time; the snackbar offers it when `HELLO` is missing, invalid or older than
`PACKAGED_FIRMWARE_VER`.

## Decision

- **Oracle:** the vector generator compiles the unmodified `FirmwareUtils`.
  - Stubs replace `Context`, `Resources`, `UsbSerialPort`, `R` and slf4android.
  - The library is esp32-flash-lib at Android's version.
  - It flashes synthetic images into a fake ESP32 ROM bootloader.
  - `flasher.json` records the transcript in order: serial parameters, DTR/RTS,
    every written and answered byte, and the callbacks. It covers a full flash, a
    wrong MD5 and a silent device.
  - The library's reply timeouts (100 ms) run in real time, so a stalled CI
    runner can make it miss a reply and retry. The generator therefore flashes
    once to warm up and keeps a transcript only when two flashes in a row produce
    it (at most five attempts).
  - `packaged-firmware.json` pins `PACKAGED_FIRMWARE_VER` against
    `KV4P.packagedFirmwareVersion`.
  - The generator copies the stub unchanged into `KV4PFlasher`'s resources;
    `make vectors-check` checks it.
- **Port:** `ESP32Flasher` ports the sequence and the protocol layer with the same
  packets, timeouts and SLIP rules.
  - SLIP escapes are shared with `KISS.escape`.
  - It compresses with the system zlib, which produces Java's bytes.
  - It replays the transcripts byte for byte on a virtual clock (`VirtualClock` in
    `KV4PTestSupport`).
- **Serial port:** `SerialBootloaderPort` adapts the existing `SerialPort` and adds
  `setBaudRate` (termios, `IOSSIOSPEED` for 921600). Reads have a timeout, as
  `UsbSerialPort.read(…, 100)` does.
- **Images:** the macOS app bundles the four files by reference to
  `android-src/KV4PHT/app/src/main/res/raw/`. They are not copied into the repo.
  `FirmwareImages.packaged(in:)` loads them by Android's names.
- **View model:**
  - It offers *Update firmware…* when a USB device is selected and the app has the
    images.
  - It flags an outdated radio when `HELLO` is missing, invalid or older than the
    packaged version.
  - It disconnects, flashes with progress, and reconnects after success.
- **Hardware check:** `kv4p-probe --flash <directory>` flashes any image set with
  the same code. Developers can use it, for example, for firmware built from
  `microcontroller-src`.

## Consequences

- **Firmware version bump:** after an upgrade to a new packaged version
  (`firmware_v18.bin`), the vector fails until `KV4P.packagedFirmwareVersion` is
  updated. The Xcode file reference must be updated too; the build fails loudly
  until it is.
- **BLE downgrade:** the packaged Android image (version 17) has no Bluetooth LE
  service, while firmware built from the current source has one with the same
  version number. Flashing the packaged image therefore removes BLE from such a
  radio. The manual says so; an upstream version bump would resolve it.
- **Failed flash:** the ROM bootloader stays available, so the radio can always
  be flashed again.
- **iOS:** the radio's USB port cannot be used, so iOS offers no update. When the
  firmware is outdated and the app has no flasher, `isWebFlasherNeeded` shows a
  notice. It links to the web flasher (`https://kv4p.com/firmware.html`) and to
  the manual's firmware section (`FirmwareHelp`). This was added in milestone 2.4.
