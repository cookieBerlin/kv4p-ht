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
- A kv4p HT radio with firmware version 17 or later. Bluetooth LE needs a build
  that includes the BLE service; the version 17 image of the Android app does not
  (see [FAQ](faq.md#which-firmware-do-i-need)). USB works with both.
- A valid amateur radio license to transmit.

## Installation

*Planned:* signed macOS builds and TestFlight builds for iOS/iPadOS will be linked
here.

🖥 To build from source, open `apple-src/App/KV4PHT.xcodeproj` in Xcode and run
the `KV4PHT` scheme (signed to run locally, no developer account needed), or see
[`apple-src/CLAUDE.md`](../../apple-src/CLAUDE.md).

## Connecting the radio

Choose the connection under **Radio** and click **Connect**:

- **Bluetooth:** power on the radio; the app connects to the first kv4p HT it
  finds. Allow Bluetooth access when macOS asks. The radio serves one Bluetooth
  connection at a time, so disconnect other apps first.
- **USB (🖥 only):** connect the radio by USB cable; it appears as
  `USB cu.usbserial-…`. The app restarts the radio when connecting, so it
  reports itself.
- **Simulator:** a built-in simulated radio, to try the app without hardware.

After connecting, the app shows the firmware version, RF module (VHF/UHF) and
frequency range. *Connected, applying settings…* means the radio has not yet
confirmed the latest change. **Disconnect** ends the session; the radio keeps its
settings.

## Receiving

- **Frequency:** type it in MHz and press Return. As in the Android app, `1467`
  becomes 146.7 MHz and frequencies outside the module range are set to the
  nearest limit. RX and TX use the same frequency (simplex); repeater offsets come
  with memories.
- **Bandwidth:** 12.5 or 25 kHz. **Squelch:** 0 (open) to 8.
- **TX/RX tone (CTCSS):** one of the 38 standard tones or *None*.
- **High power** and the **audio filters** (pre-emphasis, high-pass, low-pass).
- **S-meter:** S0…S9, then S9+20 to S9+60, and *Overload*.
- **Squelch indicator:** *Open* while a signal is received and played, *Closed*
  otherwise. The radio mutes the audio itself while the squelch is closed.
- **Volume:** the slider under **Audio** sets the playback volume in the app; the
  Mac's own volume applies on top. The audio plays on the current output device
  and moves along when you plug in headphones.
- **Simulator:** *Simulate a received signal* plays a 1 kHz tone with the squelch
  open.

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

The app warns when the radio's firmware is older than required.

- 🖥 *Planned:* connect the radio by USB and start the update from the notice or
  from Settings. Do not disconnect the cable until the update has finished and
  been verified. If an update fails, simply start it again.
- 📱 Updating from iPhone or iPad is not possible. Use the web flasher on the
  project website (desktop Chrome or Edge), the Android app or a Mac.

## Troubleshooting

| Message | What to do |
|---|---|
| *The radio did not answer.* | Switch the radio on; it needs firmware 17 or later. |
| *Firmware … is too old.* | Update the firmware (see [Firmware updates](#firmware-updates)). |
| *The SA818 radio module did not respond.* | Restart the radio. The app sends no settings in this state, because the firmware would stop responding. |
| *This device is not a kv4p HT, or its firmware has no Bluetooth LE service.* | Use USB, or update to firmware with Bluetooth LE ([FAQ](faq.md#which-firmware-do-i-need)). |
| *Bluetooth access is not allowed.* | System Settings → Privacy & Security → Bluetooth. |
| *… cannot be opened.* | Close other apps that use the USB port. |
| *The audio output cannot be started.* | Check the output device in System Settings → Sound, then connect again. The radio works without audio. |

See also the [Apple FAQ](faq.md) and the general [FAQ](../../FAQ.md).

## Hardware test checklist

Used by developers before merging a milestone that touches hardware behaviour:

- [ ] Connect via BLE; firmware version and module type shown correctly
      (until the app exists: `cd apple-src && swift run kv4p-probe --ble`).
- [ ] 🖥 Connect via USB (`swift run kv4p-probe --serial`; add `--reset` if the
      radio was already running, so it restarts and sends `HELLO`).
- [ ] RX audio continuous for 10 minutes without drop-outs, over BLE and USB
      (with a signal on the frequency, or `swift run kv4p-sim-peripheral
      --signal` on a second Mac). `swift run kv4p-probe --ble --listen 600`
      reports the block rate, the largest gap and the underruns the jitter
      buffer would have.
- [ ] PTT into a dummy load; TX stops when PTT is released and when the link drops.
- [ ] Reconnect after radio power cycle.
- [ ] Out-of-range frequency is rejected.
- [ ] Tuning is applied and confirmed by the radio
      (`swift run kv4p-probe --serial --reset --tune 145.525`, then back).
