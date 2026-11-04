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
  puts out audio. Otherwise there is no tap, and no dot in the menu bar.
- **Settings:** *Keep playing* (default) and *Mute other apps*, and the time before other
  apps return. The default differs from iOS, as muting needs the *System Audio Recording*
  permission, which should be a choice.
- **The permission** is asked for when the user chooses muting: only a running tap makes
  the system ask, so the tap runs for a moment then. There is no public way to read the
  state of this permission, so the settings explain where to allow it.

## Consequences

- Other apps run on silently, so a video or podcast goes on without being heard. Pausing
  them is not possible for all apps.
- macOS shows its recording dot in the menu bar while other apps are muted, and the app
  needs to explain that it records nothing.
- A tap belongs to one output device, so the adapter builds a new one when the user changes
  it.
- Hardware test HW-26 covers the permission, a change of output device, and a crash, which
  should bring other apps back.
