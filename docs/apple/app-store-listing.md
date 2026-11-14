# App Store listing

The texts of the product page in App Store Connect, in English only ([release plan](release.md)). They are pasted
there by hand, field by field; the limit of each field is in its heading. The notes for App Review are in
[app-review-notes.md](app-review-notes.md), the screenshots come from `make screenshots`.

## App information

| Field | Value |
|---|---|
| Name (30) | kv4p HT (by DB3AC) |
| Subtitle (30) | Ham radio for the kv4p HT |
| Primary category | Utilities |
| Secondary category | Reference |
| Age rating | 4+; no item of the questionnaire applies. Messages over APRS are not moderated, so *Unrestricted Web Access* and *User-Generated Content* are answered for APRS-IS, see below. |
| Copyright | 2026 DB3AC |
| Support URL | <https://cookieberlin.github.io/kv4p-ht/support.html> |
| Marketing URL | <https://cookieberlin.github.io/kv4p-ht/> |
| Privacy Policy URL | <https://cookieberlin.github.io/kv4p-ht/privacy.html> |

**Age rating and APRS:** the app shows APRS messages and packets from other radio amateurs, received on air and,
when the user turns it on, from the internet through APRS-IS. They are not filtered. The questionnaire's item on
user-generated content is answered with that in mind; the answer is chosen in App Store Connect at the release.

## Promotional text (170)

Control the open source kv4p HT handheld radio from your iPhone, iPad or Mac: voice on 2 m or 70 cm, APRS messages
and maps, FreeDV digital voice.

## Description (4000)

kv4p HT turns your iPhone, iPad or Mac into a ham radio transceiver, together with the kv4p HT: an open source
handheld radio for 2 m or 70 cm, a small board without a screen or buttons of its own, which the app controls.

This app is an unofficial port for Apple devices by DB3AC, written in Swift for iPhone, iPad and Mac. It is not
affiliated with the kv4p HT project, which makes and sells the radio. You need the radio to use it on air; see
kv4p.com for how to build or buy one.

RECEIVE AND TRANSMIT
• Push to talk, with the button or, on the Mac, the space bar
• Squelch, S-meter, and tuning by typing or digit by digit, within the ham bands
• Repeater shift, CTCSS tones, and an access tone of 1000, 1450, 1750 or 2100 Hz

MEMORIES AND SCANNING
• Memories in groups, for frequencies, repeaters and beacons
• A scan that stops on signals
• Imports of RepeaterBook and DARC repeater lists

APRS
• Packets, messages and chats with other stations
• Position beacons, a fill-in digipeater, and an iGate over APRS-IS
• Weather reports, objects, and a map of the stations

FREEDV
• FreeDV 2400B digital voice with Codec2, on the same FM radio

ON ALL YOUR DEVICES
• Bluetooth LE on iPhone, iPad and Mac, and USB on the Mac
• Memories, groups and your callsign in your own iCloud account
• On iPhone and iPad, audio and APRS go on with the screen locked
• The Mac app writes the firmware the app needs to the radio over USB

TRY IT WITHOUT A RADIO
A built-in radio simulator shows every function without hardware.

PRIVATE AND OPEN SOURCE
No account, no ads, no tracking. The developer collects no data. The app is free software under the GNU GPL 3.0;
the source code is on GitHub.

REQUIREMENTS
• A kv4p HT radio with the firmware for this app, the nightly build of the kv4p HT project. The Mac app can write it.
• A valid amateur radio licence to transmit. Receiving works without one.

## Keywords (100)

ham radio,amateur radio,APRS,FreeDV,transceiver,repeater,VHF,UHF,2m,70cm,callsign,walkie talkie

The name and the subtitle count as keywords already, so *kv4p*, *HT* and *ham* need not be repeated; Apple
recommends commas without spaces.

## What's New in This Version (4000)

Generated at each release from the version's section of the
[changelog](../../apple-src/App/KV4PHT/CHANGELOG.md) (ADR-0069). For 1.0.0:

The first release in the App Store.

## Screenshots

From `make screenshots`, in `.build/screenshots/store/<device>/`, in the order of their file names:

| Device in App Store Connect | Folder | Size in pixels |
|---|---|---|
| iPhone with Dynamic Island (medium display) | `iphone` | 1206 × 2622 |
| iPad 13-inch display | `ipad` | 2064 × 2752 |
| Mac | `mac` | 2560 × 1600 |
