# ADR-0030: The iOS audio session

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

On iOS and iPadOS, apps share the audio hardware through `AVAudioSession`.
Without a session category, `AVAudioEngine` cannot record. Without
`defaultToSpeaker`, *play and record* plays on the earpiece. The system also
reports events the app must handle:

- interruptions (calls, Siri, alarms);
- lost devices (a headset is unplugged or switched off);
- media service resets.

macOS has no audio session. `AVAudioEngineOutput` already follows output device
changes there ([ADR-0020](0020-rx-audio-pipeline.md)).

Android requests transient audio focus while the squelch is open, so other apps
duck. It does not stop a transmission when a headset is lost.

## Decision

- **`AudioSession`** (KV4PAudio) is a protocol with `activate()`, `deactivate()`
  and an `events` stream of `AudioSessionEvent`: `interruptionBegan`,
  `interruptionEnded(shouldResume:)`, `deviceUnavailable` and
  `mediaServicesReset`.
- **`AVAudioSessionAdapter`** (iOS only, excluded from coverage per
  [ADR-0011](0011-coverage-policy.md)) implements it:
  - category `playAndRecord`, mode `default`;
  - options `defaultToSpeaker`, `allowBluetoothHFP`, `allowBluetoothA2DP` and
    `mixWithOthers`, so the radio plays on the speaker or a headset and other
    apps keep playing;
  - it maps the interruption, route change (`oldDeviceUnavailable`) and media
    services reset notifications to events.
- **`RadioViewModel`** owns the logic:
  - It activates the session before it starts the audio output, and deactivates
    it after the output stops on disconnect.
  - An interruption ends the transmission and stops the output. When it ends
    with `shouldResume`, the audio starts again. Otherwise the screen says *The
    audio was interrupted. Connect again to listen.*
  - A lost device ends the transmission, so it does not go on with another
    microphone. Reception continues on the new route.
  - A media services reset ends the transmission and restarts the audio. Every
    start creates a new engine.
  - Events while disconnected are ignored.
- The macOS composition passes no session.
- **Settings hints:** the messages for denied Bluetooth and microphone access name
  *Privacy & Security* without the name of the settings app, which is *System
  Settings* on macOS and *Settings* on iOS.
- **Bluetooth LE:** `CoreBluetoothCentral` and `BLELink` need no change for iOS.
  They already take the write lengths and the write-without-response flow control
  from the system. Background operation and state restoration are milestone 2.2.

## Consequences

- **Not in this milestone:** ducking other apps while the squelch is open, as
  Android does, is not implemented yet. With `mixWithOthers`, other apps play
  alongside the radio.
- **Bluetooth headset quality:** with a hands-free headset (HFP), iOS records and
  plays at 8 or 16 kHz, depending on the headset. The radio's audio is 16 kHz
  narrowband FM voice, so little is lost.
- **Verification:** the adapter is verified by the hardware checklist (a call
  during reception and during a transmission, and unplugging a headset).
