# Hardware tests

The tests that only real hardware can confirm. Every test has an ID. A test stays
open until the maintainer marks it as done for that platform.

**Status:** ⬜ open · ✅ done · – does not apply. iOS means iPhone and iPad.

| ID | Test | Mac | iOS |
|---|---|---|---|
| [HW-01](#hw-01) | BLE connection, firmware and module type | ⬜ | ⬜ |
| [HW-02](#hw-02) | USB connection | ⬜ | – |
| [HW-03](#hw-03) | RX audio for 10 minutes | ⬜ | ⬜ |
| [HW-04](#hw-04) | PTT into a dummy load | ⬜ | ⬜ |
| [HW-05](#hw-05) | Reconnect after a power cycle | ⬜ | ⬜ |
| [HW-06](#hw-06) | Out-of-range frequency | ⬜ | ⬜ |
| [HW-07](#hw-07) | Tuning confirmed by the radio | ⬜ | ⬜ |
| [HW-08](#hw-08) | APRS reception | ⬜ | ⬜ |
| [HW-09](#hw-09) | APRS message and acknowledgement | ⬜ | ⬜ |
| [HW-10](#hw-10) | APRS-IS feed and iGate | ⬜ | ⬜ |
| [HW-11](#hw-11) | Position beacon and digipeating | ⬜ | ⬜ |
| [HW-12](#hw-12) | Memory with offset and tone, scan | ⬜ | ⬜ |
| [HW-13](#hw-13) | Firmware update over USB | ⬜ | – |
| [HW-14](#hw-14) | FreeDV 2400B | ⬜ | ⬜ |
| [HW-15](#hw-15) | Audio session | – | ⬜ |
| [HW-16](#hw-16) | Background operation | – | ⬜ |
| [HW-17](#hw-17) | Settings survive a restart | ⬜ | ⬜ |
| [HW-18](#hw-18) | Outdated firmware notice | – | ⬜ |
| [HW-19](#hw-19) | Layouts on real devices | – | ⬜ |
| [HW-20](#hw-20) | Permissions on first use | ⬜ | ⬜ |
| [HW-21](#hw-21) | Choosing a radio over Bluetooth | ⬜ | ⬜ |

## TestFlight

`make testflight` writes the open tests of each platform, with their IDs and titles,
to `.build/testflight/WhatToTest-<platform>.txt`. Paste that text into *What to Test*
of the build in App Store Connect. A test leaves the list once it is marked as done
here. The steps stay in this document.

## Test steps

Transmit only into a dummy load, and only with a valid amateur radio licence.

### HW-01

Connect over BLE. The firmware version and the module type are shown correctly.
Without the app: `cd apple-src && swift run kv4p-probe --ble`.

### HW-02

Connect over USB. Without the app: `swift run kv4p-probe --serial`; add `--reset`
if the radio was already running, so that it restarts and sends `HELLO`.

### HW-03

RX audio plays for 10 minutes without drop-outs, over BLE and on the Mac also over
USB. Use a signal on the frequency, or `swift run kv4p-sim-peripheral --signal` on
a second Mac. `swift run kv4p-probe --ble --listen 600` reports the block rate, the
largest gap and the underruns the jitter buffer would have.

### HW-04

PTT into a dummy load, over BLE and on the Mac also over USB. *On air* is shown and
a second receiver hears the voice clearly. TX stops when PTT is released and when
the link drops: switch off Bluetooth or pull the cable while transmitting.

### HW-05

Switch the radio off and on. The app connects again.

### HW-06

An out-of-range frequency is rejected.

### HW-07

Tuning is applied and confirmed by the radio. Without the app:
`swift run kv4p-probe --serial --reset --tune 145.525`, then back.

### HW-08

Tune to the regional APRS frequency. Packets appear in the APRS tab and match what
the Android app shows for the same packets.
`swift run kv4p-probe --ble --tune 144.8 --listen 600` prints them.

### HW-09

Send an APRS message to a second station or the Android app, into a dummy load
nearby. It arrives, and the acknowledgement turns the message *delivered*. A
message to your own callsign is acknowledged.

### HW-10

With *Show nearby APRS-IS packets* on, internet packets appear. With the iGate on,
a received RF packet shows up on aprs.fi as gated by your callsign.

### HW-11

Send a position beacon into a dummy load. A second receiver decodes the position
and the symbol. With digipeating on, a WIDE1-1 packet is repeated once.

### HW-12

Tune a memory with offset and tone. A second radio hears the TX on the offset
frequency with the tone. The scan stops on a busy memory.

### HW-13

Choose *Update firmware…*, or run `swift run kv4p-probe --flash <directory>` with
images built from `microcontroller-src`. The update flashes and verifies, and the
radio answers afterwards. The image the app ships has no Bluetooth LE, so the
radio answers over USB only until images built from `microcontroller-src` are
flashed again.

### HW-14

Use FreeDV 2400B with a second FreeDV station, such as another kv4p HT with the
Android app, into a dummy load. Voice is understood in both directions. Analog
signals keep the squelch closed in FreeDV mode.

### HW-15

RX plays on the speaker and on a Bluetooth headset. A phone call during reception
pauses the audio, and it resumes afterwards. A call or an unplugged headset during
a transmission ends it.

### HW-16

With the screen locked for 10 minutes, RX audio plays without drop-outs over BLE
and APRS packets keep arriving. Switching off the radio while the screen is locked
shows the lost connection when the app is opened.

### HW-17

Change sticky PTT, mic gain, the TX limits, the APRS settings and the memory group.
After a restart of the app, they are unchanged.

### HW-18

Connect a radio with outdated firmware. The radio tab shows the notice, with links
to the web flasher and the manual.

### HW-19

On an iPhone and an iPad, in portrait and landscape, all tabs are usable and PTT is
easy to reach. On an iPad, the app also works in a resized window.

### HW-20

On a fresh install from TestFlight, the app asks for Bluetooth, the microphone and
the location when each is first needed. Denying Bluetooth or the microphone shows
the hint to the system settings.

### HW-21

With two radios on, or one radio and `swift run kv4p-sim-peripheral` on a second Mac,
both appear under **Radio**. The app connects to the one you choose. After a restart
of the app, that radio is still chosen and the app connects to it. A radio you
switched off stays in the list, and connecting to it does not reach another radio.
