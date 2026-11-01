# kv4p HT for Apple — FAQ

For general questions about the radio, see the main [FAQ](../../FAQ.md).

## Is there an app for iPhone, iPad and Mac?

It is in development. macOS (Apple Silicon) comes first, iOS and iPadOS follow.
See the [roadmap](04-roadmap.md) for the current status.

## Why Bluetooth instead of USB on iPhone and iPad?

iOS and iPadOS only allow USB accessories that are certified in Apple's MFi
program, which requires paid licensing and hardware changes. The radio's
firmware already offers a Bluetooth LE connection that works on all Apple
devices without certification. On a Mac, both Bluetooth LE and USB work.

## Which firmware do I need?

Firmware with Bluetooth LE support. The app shows a notice if your firmware is
too old.

Careful with version 17: the firmware image shipped with the Android app
(`firmware_v17.bin`) reports version 17 but has **no** Bluetooth LE service; BLE
was added to the source later without a new version number. Such a radio works
over USB (Mac) but cannot be found over Bluetooth. Firmware built from the
current source sets the FreeDV feature flag, which the older image lacks.

## Can I update the firmware from the Apple app?

On a Mac, yes: connect the radio by USB and choose **Update firmware…**
([Firmware updates](manual.md#firmware-updates)). It writes the firmware the
Android app ships, which has no Bluetooth LE. On iPhone and iPad this is not possible because iOS does not allow
access to the radio's USB port; use the web flasher on the project website with
desktop Chrome or Edge, the Android app, or a Mac. See
[Firmware updates](manual.md#firmware-updates).

## Which Macs are supported?

Macs with Apple Silicon running macOS 26 or later. Intel Macs are not supported.

## Does the Apple app have the same features as the Android app?

That is the goal: receive, transmit, memories, scanning, APRS and FreeDV. Feature
parity is tracked in the [feasibility analysis](01-feasibility.md#feature-inventory-android-app).
Firmware flashing is available on macOS only.

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
The firmware image shipped with the Android app has no FreeDV modem; firmware
built from the current source has it ([Which firmware do I need?](#which-firmware-do-i-need)).

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

## Can I import my memories from the Android app?

Not yet; the Android app has no export. RepeaterBook CSV exports can be
imported (see the [manual](manual.md#memories-and-scanning)).

## Why does the app not download repeaters from RepeaterBook itself?

RepeaterBook requires signing in. The Android app embeds the RepeaterBook web
page for that; on the Mac you download the CSV export in your browser and import
the file, which needs no password in the app.

## Why does a packet show a strange comment such as "null INVALID position format."?

The Apple app decodes APRS exactly like the Android app, which uses the
java-aprs library. Packets that library cannot decode, or decodes oddly, look the
same in both apps.

## Does the app collect personal data?

No data is sent anywhere except what you configure: APRS packets you transmit or
send to APRS-IS contain your callsign and, if enabled, your position. The
microphone is only on while PTT is pressed, and its audio goes only to the radio.
Your location is only read while position beacons or the APRS-IS feed are on. It
is sent over RF in beacons; for the feed, it goes to the APRS-IS server as the
centre of the 50 km filter. With the iGate on, received packets and your own APRS packets go
to APRS-IS, which is public.
