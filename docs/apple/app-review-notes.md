# App Review notes

Text for the *App Review Information → Notes* field in App Store Connect. The
contact details are entered there and stay out of this repository.

## Notes

kv4p HT controls the kv4p HT, an open source handheld amateur radio, over
Bluetooth LE. Real use needs the radio, because the phone has no amateur radio
transmitter or receiver of its own.

**Testing without a radio:** the app has a built-in simulated radio. On the Radio
tab, choose **Simulator** under **Radio** and tap **Connect**. Tuning, receiving,
transmitting, memories and APRS can then be used without hardware.
Source code: https://github.com/cookieBerlin/kv4p-ht

**Licence:** transmitting on air requires an amateur radio licence. The simulator
sends nothing on air.

**Background modes:**

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
