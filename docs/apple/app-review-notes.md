# App Review notes

Text for the *App Review Information → Notes* field in App Store Connect. The
contact details are entered there and stay out of this repository.

## Notes

kv4p HT controls the kv4p HT, an open source handheld amateur radio, over
Bluetooth LE. Real use needs the radio, because the phone has no amateur radio
transmitter or receiver of its own.

**Testing without a radio:** the app has a built-in simulated radio. At the top of
the main screen, choose **Simulator** under **Radio** (on an iPhone, tap the chosen
radio first) and tap **Connect**. At the first start, enter any callsign, such as N0CALL, as
transmitting is otherwise off. Tuning, receiving, transmitting, memories and APRS can then
be used without hardware.
Source code: https://github.com/cookieBerlin/kv4p-ht

**Mute other apps (Mac):** if the user chooses this in the settings, the app uses a
Core Audio tap to silence other apps while the radio receives or transmits. It requests
no permission and records, stores and sends nothing.

**iCloud:** the app keeps a few settings, such as the callsign, in the user's iCloud
key-value store, and the memories in the user's private CloudKit database, so that they reach
the user's other devices. The background mode `remote-notification` reports their changes. It can be turned off under
Settings, Station.

**Licence:** transmitting on air requires an amateur radio licence. The simulator
sends nothing on air.

**On the Mac:** the radio can also connect over USB, and the app can write one of the two
firmwares it contains to the radio over USB, on the user's choice. It downloads no firmware. That
is why the Mac app uses the serial and USB entitlements. With the simulator, the update writes
nothing to a device. On iPhone and iPad there is no firmware update.

**Background modes (iOS):**

- `audio`: received radio audio keeps playing with the screen locked.
- `bluetooth-central`: the connection to the radio stays up with the screen
  locked.

**Permissions, each asked for when first needed:**

- Bluetooth: connects to the radio.
- Microphone: transmits the user's voice while the PTT button is pressed.
- Location: only for APRS position beacons, which are off by default.

**Internet:** the optional APRS-IS functions are off by default. They connect to
the public APRS-IS network to report and show packets. The app has no accounts,
analytics or advertising.

**Encryption:** the app uses no encryption beyond what the operating system
provides.
