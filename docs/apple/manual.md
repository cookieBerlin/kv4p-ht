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
- 📱 On iPhone and iPad the audio plays on the speaker, or on a connected headset
  (wired or Bluetooth). Other apps keep playing. A phone call pauses the radio's
  audio; it continues when the call ends.
- 📱 **In the background:** while the radio is connected, reception goes on
  when you lock the screen or switch to another app. This includes the audio,
  APRS, digipeating and the iGate. Disconnect to save the battery. Position
  beacons wait until the app is on screen again, because iOS only gives the app
  your location while you use it.
- **Simulator:** *Simulate a received signal* plays a 1 kHz tone with the squelch
  open.

## Transmitting

Transmitting requires a license and an antenna or dummy load.

- **Push to talk:** hold the button under **Transmit** while you speak; release it
  to return to receive. It turns red while PTT is pressed and shows *On air* once
  the radio transmits. The first time, macOS asks for microphone access.
- **Sticky PTT:** each click starts or ends the transmission, as in the Android
  app.
- **Mic gain boost:** *None*, *Low* (×1.5), *Med* (×2) or *High* (×2.5); use it
  if others hear you too quietly.
- **High power** is under **Channel**.
- The app only transmits inside the ham band: 144–148 MHz with a VHF module,
  420–450 MHz with a UHF module, including half the bandwidth at both edges.
  Narrower limits can be chosen under **TX limits**. Otherwise the screen shows
  *Can't transmit outside the ham band.*
- 📱 A phone call, or a headset that is unplugged or switched off, ends the
  transmission.
- Safety stops: the app ends a transmission after 3 minutes; the radio itself
  ends it when no audio arrives for about 0.8 s (e.g. when the connection drops)
  and after 200 s.
- After a transmission the received audio fades in again over about one second,
  as in the Android app.

## Memories and scanning

The memory list is in the sidebar.

- **Tune:** click a memory. The radio switches to its frequency, repeater
  offset (TX = RX ± offset) and tones. Frequencies outside the module range are
  set to the nearest limit, as in the Android app.
- **Add:** **+** creates a memory from the current frequency. **Edit…** and
  **Delete** are in the context menu (right-click). A memory has a name,
  frequency, offset (none, down or up, in kHz, default 600), TX and RX tone, an
  optional group and *Skip during scan*.
- **Groups:** the **Group** picker shows one group or all memories.
- **Scan:** steps through the memories shown, in order, and stays on a memory
  while a signal opens the squelch. It moves on 250 ms after the squelch closes.
  It skips memories marked *Skip during scan* and those outside the module
  range. With squelch 0 it scans with squelch 7, as in the Android app; **Stop
  scan** restores your squelch. Transmitting or tuning by hand ends the scan.
- **RepeaterBook import:** download a CSV export from
  [RepeaterBook](https://www.repeaterbook.com) in your browser (US or
  international format), then choose **Import RepeaterBook CSV…** and enter a
  group name. The app adds the repeaters the connected radio can receive, with
  offset and uplink tone. Connect the radio first.
- Memories are stored on this device.

## APRS

The **APRS** tab lists the APRS packets the radio decodes on air, newest
first: positions, messages, weather reports, objects, status reports and
station capabilities. Repeats of the same packet within 30 seconds (numbered
messages: 30 minutes) are counted (×2, ×3, …) instead of listed again. Packets
relayed by another station (third-party) show *via* that station. Tune to the
APRS frequency of your region (e.g. 144.800 MHz in Europe, 144.390 MHz in North
America). The list starts empty each time the app starts. *Only messages for
me* hides messages between other stations; messages from or to you, to `ALL`,
`QST`, `CQ` and bulletins stay, as do all positions, weather reports and
objects.

**Messages** (licence required): enter your callsign at the bottom of the APRS
tab (the app ships with none and remembers yours), a recipient and the text,
then press Return or **Send**. Without a recipient the message goes out as the
bulletin BLN1CQ.

- The message is sent on the current TX frequency, via WIDE1-1,WIDE2-1, only
  while the radio receives (not during PTT or a scan) and inside the ham band.
- Messages to a station are numbered and repeated after 15, 30, 60, 120 and
  240 seconds until the station acknowledges them. The symbol next to the
  message shows the state: waiting, delivered, rejected or not delivered.
  Tuning to another frequency ends the repeats (*not delivered*), as in the
  Android app.
- Numbered messages to your callsign are acknowledged automatically after one
  second.
- `|`, `~` and `{` are sent as spaces; text and number together are limited to
  67 characters.

**Position beacon** (licence required): turn on *Position beacon* at the bottom
of the APRS tab. The app sends your position right away and then every five
minutes, as long as the radio is connected and receiving. Choose the symbol
others see (phone, car, house, …) and, with *Approximate position*, round the
position to about 1 km. macOS asks for location access the first time; your
own beacons appear in the list. Beacons go out on the current TX frequency, or
on the APRS frequency chosen next to the symbol (144.390 … 145.825 MHz); the
radio returns to its frequency afterwards.

**Digipeat** turns the Mac into a fill-in digipeater: packets whose next hop is
`WIDE1-1` or your callsign are repeated once, with your callsign in the path.
This transmits without you pressing anything; only turn it on where a
digipeater is useful.

**APRS-IS** (internet, needs your callsign):

- *Show nearby APRS-IS packets* adds packets from the internet around your
  position (50 km) to the list; they are marked as internet-only. Without a known
  position, the server uses your last reported position.
- *iGate* passes the packets your radio receives to APRS-IS, and your own
  messages and beacons too, so stations elsewhere see them. Packets from the
  internet, marked NOGATE or RFONLY, and queries are not passed on.
- Both use `rotate.aprs2.net` and reconnect by themselves; the label next to the
  switches shows whether the app is connected. The feed works without a radio.

## FreeDV digital voice

FreeDV 2400B is digital voice on FM radios: the radio's firmware runs the
modem, the app encodes and decodes the speech with Codec2.

- Set **Voice mode** to *FreeDV 2400B* in the Radio tab. The setting needs
  firmware with the FreeDV modem; otherwise the app says so and stays analog.
- Receiving: the squelch opens only for FreeDV signals; analog stations are not
  heard in this mode. The S-meter shows the signal quality.
- Transmitting (licence required) works like analog voice: PTT, mic gain and the
  same TX limits. Stations need FreeDV 2400B to understand you.
- The radio keeps the setting while it is on, also when the app reconnects;
  after a restart it is analog again. Switch back to *Analog* for normal FM.
- Try it without a second radio: connect the **Simulator**, choose FreeDV 2400B
  and turn on *Simulate a received signal*; you hear a vowel-like test sound.

## Settings

The radio keeps its own settings (frequency, bandwidth, squelch, tones, power,
filters, voice mode) and reports them when the app connects. The app remembers
its settings between launches:

- **Radio tab:** sticky PTT, mic gain boost and the **TX limits**: 2 m from
  144 MHz to 148 or 146 MHz, 70 cm from 420 or 430 MHz to 450 or 440 MHz, as in
  the Android app. The app transmits only inside the band of the radio module.
- **APRS tab:** your callsign, position beacon with symbol, accuracy and
  frequency, digipeating, iGate, the APRS-IS feed and the list filter.
- **Memories tab:** the group shown.

**kv4p HT → About kv4p HT** shows the version and build of the app, the
firmware it ships for USB updates, and the licences of everything it contains
or is ported from, with the licence texts.

For reduced motion and live captions use the system settings (System Settings →
Accessibility); the Android app's own switches for them are not needed on the
Mac.

## Firmware updates

The app warns when the radio's firmware is older than required or missing
(*The radio needs a firmware update.*).

- 🖥 Connect the radio by USB, select it under **Radio** and choose **Update
  firmware…**, then **Flash**. The app writes firmware 17, the version the
  Android app ships, verifies it and reconnects, in less than a minute. Do
  not disconnect the cable until *Firmware updated and verified.* appears. If an
  update fails, simply start it again: the radio's bootloader is always there.
- Firmware built from the current source has Bluetooth LE; the version the app
  ships does not ([FAQ](faq.md#which-firmware-do-i-need)). Updating such a radio
  removes Bluetooth LE, so update only if the radio needs it.
- 📱 Updating from iPhone or iPad is not possible. Use the web flasher on the
  project website (desktop Chrome or Edge), the Android app or a Mac.

## Troubleshooting

| Message | What to do |
|---|---|
| *The radio did not answer.* | Switch the radio on; it needs firmware 17 or later. |
| *Firmware … is too old.* | Update the firmware (see [Firmware updates](#firmware-updates)). |
| *The SA818 radio module did not respond.* | Restart the radio. The app sends no settings in this state, because the firmware would stop responding. |
| *This device is not a kv4p HT, or its firmware has no Bluetooth LE service.* | Use USB, or update to firmware with Bluetooth LE ([FAQ](faq.md#which-firmware-do-i-need)). |
| *Bluetooth access is not allowed.* | 🖥 System Settings / 📱 Settings → Privacy & Security → Bluetooth. |
| *… cannot be opened.* | Close other apps that use the USB port. |
| *The microphone is not available.* | 🖥 System Settings / 📱 Settings → Privacy & Security → Microphone, then press PTT again. |
| *Set your callsign to send APRS messages.* | Enter your callsign in the APRS tab. |
| *Your location is unknown.* | Allow location access in System Settings → Privacy & Security → Location Services, or wait until the Mac has a location. |
| *The APRS message was not accepted for transmission.* | Wait until PTT or the scan has ended, tune inside the ham band, and use a callsign of at most six characters plus SSID. |
| *This file is not a RepeaterBook CSV export.* | Download the CSV export (not the web page) from RepeaterBook. |
| *Connect the radio first, …* | The import needs the radio's frequency range; connect, then import again. |
| *The radio did not start its bootloader.* | Check the USB cable (it must carry data) and close other apps that use the port, then update again. |
| *The radio stopped answering during the update.* / *The firmware could not be verified.* | Start the update again; it can always be repeated. |
| *The audio output cannot be started.* | Check the output device in System Settings → Sound, then connect again. The radio works without audio. |
| 📱 *The audio was interrupted. Connect again to listen.* | Another app took the audio and iOS did not hand it back. Connect again. |

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
- [ ] PTT into a dummy load, over BLE and USB: *On air* is shown, a second
      receiver hears the voice clearly, TX stops when PTT is released and when
      the link drops (switch off Bluetooth / pull the cable while transmitting).
- [ ] Reconnect after radio power cycle.
- [ ] Out-of-range frequency is rejected.
- [ ] APRS: tuned to the regional APRS frequency, packets appear in the APRS
      tab and match what the Android app shows for the same packets
      (`swift run kv4p-probe --ble --tune 144.8 --listen 600` prints them).
- [ ] APRS message to a second station (or the Android app) into a dummy load
      nearby: it arrives, the acknowledgement turns the message *delivered*;
      a message to the Mac's callsign is acknowledged.
- [ ] APRS-IS: with *Show nearby APRS-IS packets* on, internet packets appear;
      with the iGate on, a received RF packet shows up on aprs.fi as gated by
      your callsign.
- [ ] Position beacon into a dummy load: a second receiver decodes the position
      and symbol; with digipeating on, a WIDE1-1 packet is repeated once.
- [ ] Tune a memory with offset and tone: a second radio hears the TX on the
      offset frequency with the tone; scan stops on a busy memory.
- [ ] 🖥 Firmware update over USB: *Update firmware…* (or `swift run kv4p-probe
      --flash <directory>` with images built from `microcontroller-src`)
      flashes and verifies; the radio answers over USB and BLE afterwards.
- [ ] FreeDV 2400B with a second FreeDV station (another kv4p HT with the
      Android app) into a dummy load: voice is understood in both directions;
      analog signals keep the squelch closed in FreeDV mode.
- [ ] 📱 Audio session: RX plays on the speaker and on a Bluetooth headset; a
      phone call during reception pauses the audio and it resumes afterwards; a
      call or an unplugged headset during a transmission ends it.
- [ ] 📱 Background: with the screen locked for 10 minutes, RX audio plays
      without drop-outs over BLE and APRS packets keep arriving; switching off
      the radio while locked shows the lost connection when the app is opened.
- [ ] Tuning is applied and confirmed by the radio
      (`swift run kv4p-probe --serial --reset --tune 145.525`, then back).
