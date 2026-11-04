# ADR-0044: Mute other apps on the Mac

- **Status:** Proposed
- **Date:** 2026-11-04

## Context

Milestone 3.5c makes other apps get out of the way of the radio. iPhone and iPad do this
through their audio session ([ADR-0043](0043-pause-other-audio.md)), which macOS does not
have. The options on a Mac, checked against the SDK, Apple's documentation and a test build:

| Way | Result |
|---|---|
| Core Audio process tap | Mutes all apps but this one, also browsers; 31 to 83 ms in the test build |
| AppleScript | Pauses for real, but only Apple Music publishes the access group that the sandbox allows; others need a temporary exception, which App Review rarely grants |
| Voice processing ducking | Failed to initialize in the test build (`-10875`), and would be expected to change the radio's own sound |
| CallKit, LiveCommunicationKit, Push to Talk | Not available on macOS |
| Simulated media key | A toggle, which would start what does not play |
| Hog mode, system volume | Would silence this app or block the device |
| `MediaRemote` | Private API |

## Decision

- **A global tap that leaves out this app,** with `mutedWhenTapped`: it silences other
  apps only while the tap is read. The audio read is thrown away. `CoreAudioOtherAppsMute`
  (KV4PAudio) is a thin adapter.
- **`OtherAudioController` decides,** behind `OtherAudioSwitching`, which `AudioSession`
  also extends. The rules are those of ADR-0043. As the radio's output never stops, nothing
  waits in the buffer, and other apps need no wait before the app goes on.
- **Only while something plays:** the Core Audio process list says whether another process
  puts out audio.
- **Settings:** *Keep playing* (default) and *Mute other apps*, and the time before other
  apps return.
- **No permission:** the app leaves out `NSAudioCaptureUsageDescription`. In a test on a Mac,
  the system then asked nothing and showed no recording dot, and muting still worked; the
  app did not crash. With the key, the system asks for *System Audio Recording* when a tap
  starts, and shows the dot, although refusing did not stop the muting. As the app throws
  the audio away, it does not need the permission, and each new permission is a cost.

## Consequences

- Other apps run on silently, so a video or podcast goes on without being heard. Pausing
  them is not possible for all apps.
- Apple documents the key as needed to capture audio with a tap, and does not document
  muting without it. If Apple changes this, muting can stop or the app can need the key
  again, which would bring back the question and the dot. Whether App Review objects is
  unknown until the first release to the App Store.
- A tap belongs to one output device, so the adapter builds a new one when the user changes
  it.
- Hardware test HW-26 covers the permission, a change of output device, and a crash, which
  should bring other apps back.

## If this stops working

This way rests on behaviour Apple does not document, and is the choice for now, not for good.
Signs that it has to change: other apps stay audible after a macOS update, the app crashes
when a tap starts, or App Review objects to the tap. HW-26 notices the first two.

The way back is small, as it stays inside the adapter and the settings:

1. Add `NSAudioCaptureUsageDescription` to `KV4PHT-macOS-Info.plist` again. The test build
   showed that macOS then asks for *System Audio Recording* when a tap starts, and shows the
   recording dot, and that muting works.
2. Ask when the user chooses *Mute other apps*, by running the tap for a moment, so that
   the question does not come up during a call. Say in the settings where to allow it.
3. If taps cannot be used at all, AppleScript can still pause Apple Music, which publishes
   the `com.apple.Music.playback` access group for the `scripting-targets` entitlement.
   *Keep playing* stays available in any case.
