# kv4p HT for Apple — User Manual

> **Status:** the Apple app is in development and not released yet. This manual
> grows with each feature; sections marked *planned* describe intended behaviour.
> Platform notes: 🖥 macOS · 📱 iOS/iPadOS.

## Contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [Connecting the radio](#connecting-the-radio)
4. [Receiving](#receiving)
5. [Transmitting](#transmitting)
6. [Memories and scanning](#memories-and-scanning)
7. [APRS](#aprs)
8. [FreeDV digital voice](#freedv-digital-voice)
9. [Settings](#settings)
10. [Firmware updates](#firmware-updates)
11. [Troubleshooting](#troubleshooting)
12. [Hardware test checklist](#hardware-test-checklist)

## Requirements

- 🖥 Mac with Apple Silicon, macOS 26 or later.
- 📱 iPhone or iPad with iOS/iPadOS 26 or later *(phase 2)*.
- A kv4p HT radio with firmware version 17 or later (BLE support).
- A valid amateur radio license to transmit.

## Installation

*Planned.* Signed macOS builds and TestFlight builds for iOS/iPadOS will be linked
here. To build from source, see [`apple-src/CLAUDE.md`](../../apple-src/CLAUDE.md).

## Connecting the radio

*Planned.*

- **Bluetooth LE (all platforms):** power on the radio; the app lists devices
  named `kv4p-XXXXXX`. Select one to connect. Grant Bluetooth permission when asked.
- **USB (🖥 only):** connect the radio by USB cable; the app detects the serial
  port automatically.
- After connecting, the app shows the firmware version, RF module (VHF/UHF) and
  supported frequency range.

## Receiving

*Planned.* Frequency entry, bandwidth (12.5/25 kHz), CTCSS, squelch, S-meter.

## Transmitting

*Planned.* Push-to-talk (hold or sticky), microphone gain, high/low power.
Transmitting requires a license and an antenna or dummy load.

## Memories and scanning

*Planned.* Memories, groups, scan, RepeaterBook import.

## APRS

*Planned.* Messages, position beacons, digipeating, APRS-IS. Set your own callsign
in Settings before transmitting; the app ships with no callsign configured.

## FreeDV digital voice

*Planned.* FreeDV 2400B mode, if the firmware reports support.

## Settings

*Planned.*

## Firmware updates

The app warns when the radio's firmware is older than required. Update the
firmware with the web flasher on the project website (desktop Chrome or Edge) —
the Apple app does not flash firmware itself
([ADR-0009](adr/0009-firmware-updates.md)).

## Troubleshooting

See also the [Apple FAQ](faq.md) and the general [FAQ](../../FAQ.md).

## Hardware test checklist

Used by developers before merging a milestone that touches hardware behaviour:

- [ ] Connect via BLE; firmware version and module type shown correctly.
- [ ] 🖥 Connect via USB.
- [ ] RX audio continuous for 10 minutes without drop-outs.
- [ ] PTT into a dummy load; TX stops when PTT is released and when the link drops.
- [ ] Reconnect after radio power cycle.
- [ ] Out-of-range frequency is rejected.
