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

On a Mac, yes: connect the radio by USB and use the firmware update function
*(planned)*. On iPhone and iPad this is not possible because iOS does not allow
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

Development builds include a built-in radio simulator, and a Mac can act as a
virtual radio over Bluetooth for another device: `cd apple-src && swift run
kv4p-sim-peripheral` advertises as `kv4p-000000` until stopped
([ADR-0014](adr/0014-radio-simulator.md)). The Mac running it cannot connect to
itself; use a second Mac, iPhone/iPad or the Android app.

## Does the app collect personal data?

No data is sent anywhere except what you configure: APRS packets you transmit or
send to APRS-IS contain your callsign and, if enabled, your position.
