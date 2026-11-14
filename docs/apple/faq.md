# kv4p HT for Apple — FAQ

For general questions about the radio, see the main [FAQ](../../FAQ.md).

## Is there an app for iPhone, iPad and Mac?

Yes. All three, on the Mac with Apple Silicon, get test builds through TestFlight.
There is no date for a release in the App Store. See the [roadmap](04-roadmap.md) for the
current status.

## How do I get the test builds?

Through Apple's TestFlight app, with the [public invitation](https://testflight.apple.com/join/YyNEfBpK). The app
is not in the App Store yet. See the [manual](manual.md#installation) and the
[website](https://cookieberlin.github.io/kv4p-ht/).

## What changed in a build?

The [changelog](../../apple-src/App/KV4PHT/CHANGELOG.md) lists what changed in each TestFlight build, newest first; it
is also on the [website](https://cookieberlin.github.io/kv4p-ht/changelog.html). In the app, **What's New** in About
shows it, and after an update the app shows once what is new in that build.

## Why Bluetooth instead of USB on iPhone and iPad?

iOS and iPadOS only allow USB accessories that are certified in Apple's MFi
program, which requires paid licensing and hardware changes. The radio's
firmware already offers a Bluetooth LE connection that works on all Apple
devices without certification. On a Mac, both Bluetooth LE and USB work.

## Which firmware do I need?

The nightly build of the kv4p HT project, which the Mac app contains. The app shows a notice
if your radio has another one.

Careful with version 17: two firmwares report it. The released one, which the Android app 2.0
ships, sends its voice as Opus and has no Bluetooth LE. The nightly build sends it as ADPCM, has
Bluetooth LE and FreeDV, and works with this app. The feature flag for FreeDV tells them
apart, which is how the app recognises and refuses the released one: with it, the app would
play nothing and PTT would transmit silence.

| App | Firmware 15 | Firmware 17 | Nightly build |
|---|---|---|---|
| This app | no connection | refused | ✅ USB and Bluetooth LE |
| Android 1.9.5–1.9.9.3 | ✅ | no connection | no connection |
| Android 2.0 | no connection, offers an update | ✅ USB | connects, no voice |
| Android nightly | no connection, offers an update | connects, no voice | ✅ USB and Bluetooth LE |

This comes from the source and the published firmware; only this app with the current source has
been tried on a radio.

## Can I update the firmware from the Apple app?

On a Mac, yes: connect the radio by USB and choose **Update firmware…**
([Firmware updates](manual.md#firmware-updates)). You choose between the nightly build for this
app and firmware 17, to go back to the Android app. On iPhone and iPad this is not possible because
iOS does not allow access to the radio's USB port; use a Mac or the Android nightly app. The
project's [web flasher](https://kv4p.com/firmware.html) offers only firmware 17, which this app
refuses.

## Can I transmit with the keyboard on a Mac?

Yes: hold the space bar for **Push to talk**, and ⌥ with the space bar for the access tone that opens a repeater.
They work while the main window is in front and no text field takes the typing, so the space bar still types a
space in the frequency field and in a message. Letting go ends the transmission, and so does a switch to another
window or app, as its release would not reach the app. ⌘K connects and disconnects. The *Radio* menu lists all three.

## Which Macs are supported?

Macs with Apple Silicon running macOS 27 or later. Intel Macs are not supported.

## Does the Apple app have the same features as the Android app?

That is the goal: receive, transmit, memories, scanning, APRS and FreeDV. Feature
parity is tracked in the [feasibility analysis](01-feasibility.md#feature-inventory-android-app).
Firmware flashing is available on macOS only.

## Does the iPhone keep receiving with the screen locked?

Yes, while the radio is connected: audio, APRS, digipeating and the iGate go on
in the background, and so do position beacons, unless you turn off *Beacon in the
background*. The system then shows its location indicator, and more battery is used.
See [ADR-0031](adr/0031-ios-background-operation.md) and
[ADR-0056](adr/0056-background-beacons.md).

## Can I try the app without a radio?

Yes: choose **Simulator** under **Radio** in the app. A Mac can also act as a
virtual radio over Bluetooth for another device: `cd apple-src && swift run
kv4p-sim-peripheral` advertises as `kv4p-sim` until stopped (add `--signal` to
receive a 1 kHz tone, or a FreeDV test sound in FreeDV 2400B mode)
([ADR-0014](adr/0014-radio-simulator.md)). The Mac running it cannot connect to
itself; use a second Mac, iPhone/iPad or the Android app.

## Which FreeDV modes does the app support?

FreeDV 2400B only, the mode the firmware's modem implements, as in the Android
app. The app uses Codec2 1.2.0 in mode 1300, built from the same upstream
source as the Android app ([ADR-0027](adr/0027-freedv-voice-and-codec2-vendoring.md)).
The firmware for this app has the modem ([Which firmware do I need?](#which-firmware-do-i-need)).

## Why do I hear audio a moment after the squelch opens?

The app buffers about 60 ms of audio before playing, so that Bluetooth timing
gaps do not cause drop-outs. If the link stalls longer, the app waits for the
buffer to fill again; it never lags behind by more than about a quarter of a
second. Right after connecting, the app stays silent for about one second, as
the Android app does: the radio sends a loud click while it starts.

## Why can't I transmit on some frequencies?

Like the Android app, the Apple app only transmits inside the 2 m (144–148 MHz)
or 70 cm (420–450 MHz) ham band, depending on the RF module. Receiving works on
the whole range of the module.

## Why does a digit of the frequency jump to another value?

A step goes to the next channel of the raster: 12.5 kHz with a narrow and 25 kHz with a wide bandwidth. A digit
smaller than the raster, such as the kHz digit, steps by one channel. A larger one steps by its value and goes to the
nearest channel, so 146.520 MHz becomes 146.625 MHz. To step by the digit exactly, as for a station off the raster,
hold ⌥ on the Mac, or hold the digit for a moment before you swipe on iPhone and iPad.

## Can I import my memories from the Android app?

Not yet; the Android app has no export. RepeaterBook CSV exports and the CSV exports of the DARC repeater lists can
be imported (see the [manual](manual.md#memories-and-scanning)).

## Why does the DARC import leave out some repeaters?

The radio is an FM radio, so only FM entries are imported; an entry without a mode counts as FM. A kv4p HT receives
2 m or 70 cm, so entries for other bands, such as 23 cm, are left out. The preview says how many entries it leaves
out and why. A beacon is imported as a beacon: it only transmits, and you listen to it.

## Why does the list show fewer memories than I imported?

With a radio connected, the list shows only the memories its module receives: a 2 m radio hides those for 70 cm,
and the other way round. The line below the list says how many are hidden. They show again when a radio for their
band is connected, and ⚙ **Settings** → *Memories* always shows all of them.

## Why does the app not download the DARC repeater lists itself?

The lists have no licence for a download by an app. You download the CSV export in your browser and import the file.

## Why does the app not download repeaters from RepeaterBook itself?

RepeaterBook requires signing in. The Android app embeds the RepeaterBook web
page for that; on the Mac you download the CSV export in your browser and import
the file, which needs no password in the app.

## Why does a packet show a strange comment such as "null INVALID position format."?

The Apple app decodes APRS exactly like the Android app, which uses the
java-aprs library. Packets that library cannot decode, or decodes oddly, look the
same in both apps.

## Why does the app name a radio, and where did `_3` go?

Mic-E radios mark themselves at the end of the comment, and `_3` is the mark of a Yaesu FT5D. The app
shows such marks as the name of the radio. A mark it does not know stays in the comment. The names come
from the [APRS device identification database](https://github.com/aprsorg/aprs-deviceid), and the
meanings of the symbols from the [aprs.fi APRS symbols index](https://github.com/hessu/aprs-symbol-index).

## Can I hide APRS?

Yes: switch off **APRS** in ⚙ **Settings → Pages**; the map can go there as well. The packets, the chats and the APRS settings go, and the
app no longer receives or sends APRS, so no beacon goes out unseen. Your APRS settings stay for when you
switch it on again ([ADR-0066](adr/0066-hideable-pages.md)).

## Why is the map empty or blurred?

The map shows only memories with a position, on the layers switched on: frequencies are off at first. Repeaters
imported from the DARC lists bring their position; for others, enter latitude and longitude in the memory. The
map comes from Apple and needs the internet; without it, only the parts seen before show
([ADR-0068](adr/0068-map.md)).

## Why is a station I chat with not on the map?

The map shows only APRS packets with a position: positions, objects and weather. A message has none, so a station
that only sends messages is not on the map. Under *Layers*, **Heard within** chooses how far back the map looks,
1 hour at first ([ADR-0068](adr/0068-map.md)).

## Does the app keep the APRS packets?

Yes, on this device only, for 30 days by default, and not synced. Packets only from the internet stay only if you
choose so. Messages to or from you always stay. Under ⚙ **Settings**, *APRS*, *History* you can change
this and delete them.

## Does the app collect personal data?

No data is sent anywhere except what you configure: APRS packets you transmit or
send to APRS-IS contain your callsign and, if enabled, your position. The
microphone is only on while PTT is pressed, and its audio goes only to the radio.
Your location is only read while position beacons or the APRS-IS feed are on, or while the APRS
list or the map is on screen, to show how far away stations and memories are; for that it stays on your device.
The map loads its tiles from Apple, which sees the part of the map you look at, but not your memories. For beacons it
is sent over RF in beacons; for the feed, it goes to the APRS-IS server as the
centre of the 50 km filter. With the iGate on, received packets and your own APRS packets go
to APRS-IS, which is public. With *iCloud sync* on, your memories, your callsign and a few settings are
kept in your own iCloud account, to reach your other devices; you can turn that off under
⚙ **Settings**, *Station*.

## Which licences apply?

The app is free software under the GNU GPL 3.0, like the whole kv4p HT project
([source code](https://github.com/cookieBerlin/kv4p-ht)). It contains Codec2 1.2.0
(GNU LGPL 2.1) and the esptool flasher stub (GNU GPL 2.0 or later), both
unmodified, and ports code from the Android app, java-aprs, javAX25 and
esp32-flash-lib. **About kv4p HT** lists them with their licence texts. It also contains the names of
the APRS symbols from the [aprs.fi symbols index](https://github.com/hessu/aprs-symbol-index)
(CC BY-SA 4.0) and the list of radios from the
[APRS device identification database](https://github.com/aprsorg/aprs-deviceid) (CC BY-SA 2.0), which it
names there.
