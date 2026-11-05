# Hardware tests

The tests that only real hardware can confirm. Every test has an ID. A test stays
open until the maintainer marks it as done for that platform.

**Status:** ⬜ open · ✅ done · – does not apply. iOS means iPhone and iPad.

| ID | Test | Mac | iOS |
|---|---|---|---|
| [HW-01](#hw-01) | BLE connection, firmware and module type | ✅ | ✅ |
| [HW-02](#hw-02) | USB connection | ✅ | – |
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
| [HW-13](#hw-13) | Firmware update over USB | ✅ | – |
| [HW-14](#hw-14) | FreeDV 2400B | ⬜ | ⬜ |
| [HW-15](#hw-15) | Audio session | – | ⬜ |
| [HW-16](#hw-16) | Background operation | – | ⬜ |
| [HW-17](#hw-17) | Settings survive a restart | ⬜ | ⬜ |
| [HW-18](#hw-18) | Outdated firmware notice | – | ⬜ |
| [HW-19](#hw-19) | Layouts on real devices | ⬜ | ⬜ |
| [HW-20](#hw-20) | Permissions on first use | ✅ | ✅ |
| [HW-21](#hw-21) | Choosing a radio over Bluetooth | ✅ | ✅ |
| [HW-22](#hw-22) | Reporting a failed connection | ⬜ | ⬜ |
| [HW-23](#hw-23) | PTT starts quickly | ⬜ | ✅ |
| [HW-24](#hw-24) | Memory editor | ⬜ | ⬜ |
| [HW-25](#hw-25) | Other audio on a real radio | – | ⬜ |
| [HW-26](#hw-26) | Mute other apps on a Mac | ⬜ | – |
| [HW-27](#hw-27) | Repeater access tone | ⬜ | ⬜ |
| [HW-28](#hw-28) | Deviation of the access tone | ⬜ | ⬜ |
| [HW-29](#hw-29) | Callsign and listen-only | ⬜ | ⬜ |
| [HW-30](#hw-30) | Settings sync between two devices | ⬜ | ⬜ |
| [HW-31](#hw-31) | Memory sync between two devices | ⬜ | ⬜ |
| [HW-32](#hw-32) | Distance to APRS stations | ⬜ | ⬜ |
| [HW-33](#hw-33) | APRS symbols and radios | ⬜ | ⬜ |
| [HW-34](#hw-34) | APRS packet types and units | ⬜ | ⬜ |
| [HW-35](#hw-35) | Beacons with the screen locked (iPhone) | – | ⬜ |
| [HW-36](#hw-36) | APRS history | ⬜ | ⬜ |

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

Tune to the regional APRS frequency. Packets appear in the APRS list and match what
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

Choose *Update firmware…*. The nightly build is preselected, with its build time, commit and
SHA-256. It flashes and verifies, and the radio answers over USB and Bluetooth LE, with sound
in both directions into a dummy load. Then flash firmware 17: the app stays disconnected and says
so, the Android app 2.0 works with the radio, and connecting from this app is refused without
anything going on air. Flash the nightly build again: a radio with a board configuration
keeps it throughout. Firmware 17 uses the larger partition table here, unlike the release.

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

Try to connect to a radio with firmware 17, which has no Bluetooth LE. The bottom of the screen
shows the notice, which points to a Mac and the Android nightly app, with a link to the manual.

### HW-19

On an iPhone and an iPad, in portrait and landscape, the header, the memories, APRS
and the settings are usable and PTT is easy to reach. On an iPad, memories and APRS
stand side by side, and a narrow window shows pages instead. On an iPhone, swiping and
the bar at the bottom change between the memories, APRS and the settings. On a Mac,
they stand side by side, and ⌘, opens the settings. All explanations are readable: tooltips on the
Mac, texts and ⓘ on iPhone and iPad.

### HW-20

On a fresh install from TestFlight, the app asks for nothing at its start. The first
**Connect** over Bluetooth asks for Bluetooth, the microphone and the location, and on
iPhone and iPad for notifications. After that, the radios appear under **Radio**.
Without the microphone, a text with **Open Settings** replaces PTT. Without the location,
the beacon switch is grey with a text below it. Without Bluetooth, **Connect** is grey
for Bluetooth radios with a text, and USB and the simulator still work.

### HW-21

With two radios on, or one radio and `swift run kv4p-sim-peripheral` on a second Mac,
both appear under **Radio**. The app connects to the one you choose. After a restart
of the app, that radio is still chosen and the app connects to it. A radio you
switched off stays in the list, and connecting to it does not reach another radio.

### HW-22

Connect over Bluetooth, then switch the radio off. On the Mac, a dialog opens once,
and the status bar shows the reason; with another app in front, the Dock icon also
bounces. On iPhone and iPad, with the app in front, the reason shows once in red above PTT.
Allow notifications at the first connection, then lock the screen and switch the radio
off: one notification arrives, and the reason shows on return. Choosing **Disconnect** reports nothing.

### HW-23

Connect the radio and press PTT. The press gives a light vibration at once (iPhone).
The button turns red without a noticeable delay, and the microphone indicator of iOS
lights only while PTT is on, not while merely connected. Moving the finger on the
button does not end the transmission.

### HW-24

Memories from an earlier version are still there after the update. In **Manage
memories…**, drag groups and memories by their handles: the order stays after a restart,
and the main list and the scan follow it. A tap opens a group or a memory. Every field of
the memory form shows its label. Move and delete several memories, rename and delete a
group. Import a RepeaterBook CSV twice into the same group: the second time, the
assistant says that the repeaters are already there.

### HW-25

Play music, then a podcast, on an iPhone connected to the radio over Bluetooth, unlocked
and locked. A second radio transmits a counted sentence: every word arrives, the podcast
pauses, the music gets quieter, and both return after the set time. Press PTT while they
play: a third radio hears no music. Unlock after a locked reception: PTT works at once. With
*Keep playing*, nothing changes. With a Bluetooth headset, repeat all of this and note
how long the first words take.

### HW-26

On a Mac, choose *Mute other apps*: the system asks nothing, and no recording dot shows.
Play music and a video in a browser. With a signal from a radio, both go silent while the
radio stays audible, and return after the set time. Press PTT while they play: a second
radio hears nothing of them. Change to headphones while they are muted: they stay silent.
Force quit the app while they are muted: they become audible.

### HW-27

Choose a tone in the settings. Hold **Tone** next to PTT, listening with a second radio:
first silence, then the tone for the set time, then the transmitter stops, also if the
button is still held. The microphone indicator stays off, and the tone plays on the device.
On an iPhone it vibrates all the time while held. Release early: the transmitter stops at
once and a message says so. A real repeater opens. Music in another app keeps playing.

### HW-28

With a deviation meter or a service monitor, measure each tone with and without
pre-emphasis at the 50 % level. Note whether the level should change, and whether the first
or last moments of the tone get lost at the transmitter.

### HW-29

Start with no callsign: the app asks, and the question closes only with a choice. Choose
*Listen only* with a radio connected: there is no PTT, no tone button and no message line, a
second radio hears nothing from a beacon, a digipeat or an acknowledgement, and reception
works. Enter a callsign: the iGate can be used. Turn *Listen only* off while PTT is not
pressed: PTT returns. Hold sticky PTT and remove the callsign in the settings: the
transmission ends at once.

### HW-30

With two devices on the same Apple ID, both signed with a team. Enter a callsign on one: after
a while it appears on the other, and the question at the start closes there. Change sticky PTT
and the beacon frequency: they follow. Remove the callsign: it goes on the other device as
well, without the question. Change the mic gain or listen only: the other device stays as it
is. Turn *iCloud sync* off on one: changes no longer pass in either direction; on again, it
catches up. Install on a new device with no settings: it changes nothing on the others.

### HW-31

With two devices on the same Apple ID, both signed with a team, and the CloudKit schema in the
development environment. Add a memory on one: after a while it appears on the other without a
restart. Rename, move to another group, sort and delete: the other device follows. With memories
that already exist on both devices, the first sync leaves one of each. Tune to a memory while
others change. Turn off the network, change on both, turn it on again: nothing is lost, and the
later change of a field counts. Turn *iCloud sync* off and restart: changes stay on the device.
A TestFlight build additionally needs the schema deployed to production.

### HW-32

With a real position and packets of stations whose place you know: distance and direction fit,
in the unit of the system. The coordinates open Apple Maps with a pin named after the station.
Before location access is decided, *Show distances* asks for it; denied, the list shows only the
coordinates, without a hint. The location indicator stays off while the APRS list is not on screen.

### HW-33

With packets of real stations on the APRS frequency, or APRS-IS: symbols show as icons with their
meaning. A Yaesu or Kenwood Mic-E radio shows its name, and no longer marks such as `_3` in the
comment. The tooltip on the Mac and holding the icon on iPhone and iPad show the details, and holding
the text of a row still selects it. A digipeater with an overlay shows its letter. The icons are
readable in light and dark mode, and the beacon symbols in the settings show theirs.

### HW-34

On the APRS frequency or with APRS-IS: a weather station shows only what it reports, and the units
follow *Units* under *APRS* in the settings, and so does the distance. A repeater object reads as
frequency, offset and range, a removed object is crossed out, and packets only from the internet and
digipeated ones are marked. Status, capabilities, telemetry and bulletins say what they are. Holding
or pointing at any icon shows its details. On a second device, *Units* follows.

### HW-35

On an iPhone with a radio, a callsign and access while using the app; only with a licence, as this
transmits. Turn the beacon on with a short interval, then lock the screen. A second radio or APRS-IS
shows the beacons at that interval, also after an hour, and the system's location indicator shows. After
ending the beacon, the indicator goes. With *Beacon in the background* off, no beacon goes out with
the screen locked, there is no indicator, and the beacon goes out when the app returns. Take away
location access or go without a position: one notice comes, not one per beacon. Note the battery used.

### HW-36

Receive packets on the APRS frequency and end the app: after a new start the list is back. Send a
message and end the app before an acknowledgement comes: after a new start it shows as not delivered,
and is not sent again. With the APRS-IS feed on, its packets stay in the list but are gone after a
restart, unless *Keep internet packets* is on; a message to you stays either way. Delete one packet
with the button on its row, and all of them in the settings. Turn *Keep packets* off and answer the
question both ways. With a long list, **Load more** brings older packets, and the app stays smooth.
Search by callsign, *For me* with a message to another SSID of yours, and *Types* find older stored packets too.
Export both formats and open the CSV in a spreadsheet: a text such as `=1+1` stays text. *Settings*, *APRS*, *Packets*
shows the list over the full height, and its filter leaves the main page alone. After a restart both filters are back.
The box on a row is filled for a stored packet and empty for one only from the internet with *Keep internet packets* off,
and *Stored packets* in the settings counts the filled ones. After an update from the version before this, the old packets are gone and the count starts again at 0.
