# ADR-0031: Background operation on iOS

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

iOS suspends an app shortly after it leaves the screen, unless it declares a
background mode and uses it:

- **`audio`** keeps the app running while its audio session plays or records.
- **`bluetooth-central`** delivers CoreBluetooth events (notifications, writes,
  disconnects) while the app is in the background.

Android runs `RadioAudioService` as a foreground service of type
`location|mediaPlayback|microphone`. RX audio, APRS, beacons, digipeating and the
iGate go on with the screen off.

While connected, the app's `AVAudioEngineOutput` renders without pause: radio
audio, or silence while the squelch is closed. The audio session is active
([ADR-0030](0030-ios-audio-session.md)).

## Decision

- **Background modes:** the iOS app declares `audio` and `bluetooth-central`.
  - Xcode's generated Info.plist has no `INFOPLIST_KEY_` setting for background
    modes. A partial `App/KV4PHT-iOS-Info.plist` therefore holds only
    `UIBackgroundModes`.
  - `Config/Base.xcconfig` sets it as `INFOPLIST_FILE` for the iOS SDKs. Xcode
    merges it with the generated keys; macOS does not use it.
- **No new code:** the app does not react to the scene phase. Because the output
  keeps rendering, the app keeps running while connected, and everything goes on
  as on Android:
  - RX audio and the S-meter;
  - received APRS packets and messages;
  - digipeating, the iGate and the APRS-IS feed;
  - an ongoing transmission.
- **Check:** `make app` builds the iOS app into `.build/app`.
  `scripts/app-plist-check.sh` then fails unless the built `Info.plist` declares
  both modes. Unit tests cannot see the app bundle, so this check guards the
  configuration.

## Consequences

- **Disconnected:** when the radio disconnects, the audio stops and iOS suspends
  the app. Reconnecting needs the app on screen, as on Android, where the user
  reconnects in the app.
- **No state restoration:** CoreBluetooth state restoration is not adopted. If iOS
  terminates the app, the system does not relaunch it for the radio.
- **Position beacons:** the app asks for location access *while using the app*
  only. In the background, iOS gives it no location, so position beacons wait
  until the app is back on screen. Android's foreground service has the
  `location` type for this. Matching it needs the `location` background mode and
  a `CLBackgroundActivitySession`, and is left for a later decision.
- **Battery:** the app uses more battery while it runs connected in the
  background. Disconnecting ends this.
- **App Review:** App Review expects a justification for both modes. kv4p HT is
  a radio receiver that plays audio and talks to its Bluetooth LE accessory, so
  it has one.
