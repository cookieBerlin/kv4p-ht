# ADR-0049: Two bundled firmwares, one for this app and one for Android

- **Status:** Proposed
- **Date:** 2026-11-04
- **Supersedes:** the firmware images part of [ADR-0009](0009-firmware-updates.md) and
  [ADR-0028](0028-firmware-flashing.md)

## Context

The Mac app flashed the firmware the Android app ships, `firmware_v17.bin`, and accepted
every radio that reports version 17 or later. A comparison of the published firmware with
the app's protocol found that this version does not suit the app:

| | v15 | v17 | Nightly |
|---|---|---|---|
| Reported version | 15 | 17 | 17 |
| Framing | `DE AD BE EF` | KISS + `KV4P` | KISS + `KV4P` |
| Voice | Opus, command `0x07` | Opus, command `0x07` | IMA ADPCM, command `0x0C` |
| Connections | USB | USB | USB, Bluetooth Classic, BLE |
| AX.25 on a set frequency (`0x0F`) | no | no | yes |
| FreeDV 2400B (feature bit 3) | no | no | yes |

This app speaks ADPCM on `0x0C`. With v17 it connects and tunes, but plays nothing, sends
no APRS and, worse, keys the transmitter without modulation. The version number does not
tell the two apart, as the nightly build also reports 17. Upstream publishes no later
release and no signatures, and the project's web flasher offers only v17.

The findings come from the source at each tag and from the published binaries.

Downloading firmware inside the app, as first planned for this milestone, is not needed:
only two versions are useful, and the nightly release is replaced in place, so a version
tested once cannot be fetched again.

## Decision

- **The Mac app bundles two firmwares,** and the user chooses at each update:
  - **Nightly, for this app:** preselected, with its build time, commit and SHA-256 shown,
    and marked as a development build of the project.
  - **Firmware 17, for the Android app:** clearly marked as such, so that a radio can go
    back to Android. It stays the file of `android-src`, so that it follows the Android app.
- **The nightly image is in the repository,** under `apple-src/App/Firmware/`, with a manifest
  of its commit, build time and SHA-256. `make nightly-firmware` replaces both on purpose,
  after checking GitHub's digest; nothing updates them by itself. A new image needs a
  hardware test.
- **The checksum is checked twice:** a test compares the committed image with the manifest,
  and the app offers the image only if it matches. This finds a damaged file; it says
  nothing about who built it, as upstream signs nothing. The existing MD5 check verifies
  what reaches the radio.
- **The other three regions are shared:** bootloader, partition table and `boot_app0` come
  from `android-src`. The partition table has the larger app partition the nightly image
  needs. A test checks that the image fits. The NVS partition, with the board configuration,
  is never written.
- **The app refuses firmware 17 without the FreeDV feature bit** with its own failure, and
  still offers the update. Nothing goes on air that way, which also gives up tuning and
  APRS reception with that firmware. The bit stands in for the voice codec: it separates all
  published images, but builds from between v17 and FreeDV would be refused as well. That is
  accepted, as they were never released.
- **After flashing firmware 17** the app does not reconnect, and says that the radio is now
  set up for Android.
- **iPhone and iPad point to a Mac or the Android nightly app,** as the web flasher can only
  write v17, which the app refuses.
- **The simulator** has one firmware choice (current, for Android, too old) instead of two
  switches, as *current without FreeDV* no longer exists. It offers placeholder firmwares,
  also on iOS, so that App Review can try the update screens.

## Consequences

- A radio can move between Apple and Android from the Mac, offline.
- The repository holds a 1.6 MB binary, and each new one adds to its history. Nightly builds
  come without upstream's release testing, which is why the hardware test is required.
- Radios with firmware 17 stop working with the app until they are updated, which needs a Mac
  or the Android nightly app. Before, they connected, but without sound.
- The app no longer downloads firmware, so the review question of [ADR-0036](0036-no-distribution-outside-app-store.md)
  stays what it was.
- When upstream releases a newer version with ADPCM, the choice and the rule can shrink again.
