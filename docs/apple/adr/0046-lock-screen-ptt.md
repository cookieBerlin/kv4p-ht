# ADR-0046: PTT from the lock screen

- **Status:** Proposed (deferred, not implemented)
- **Date:** 2026-11-04

## Context

Users may want to transmit without unlocking the iPhone. A test build found a way that works,
and this record keeps what it showed. The feature is deferred: it adds more complexity than
the app should take on for now. It stays an option for the future (milestone 3.5e).

## Options

| Way | Result |
|---|---|
| Start the microphone from the background | Not allowed: `cannotStartRecording` in the test build of 3.5c |
| `AudioRecordingIntent` with a Live Activity | Reported to fail on the lock screen, and not made for press and hold; not tried |
| Apple's Push to Talk framework | Works, see below |

## What the framework asks for

- The capabilities Push to Talk and Push Notifications, and the background mode
  `push-to-talk`. It exists on iOS and iPadOS only, not on macOS. The capability could be
  turned on for the account.
- Joining a channel needs the app in the foreground and an action of the user.
- The system owns the audio session while it is in use: Apple says to let it activate and
  deactivate the session, and to wait for `channelManager(_:didActivate:)` before recording.
- The system plays its own sounds for the microphone; custom ones are not supported.

## What a test on an iPhone showed

The test used a simulated reception, as a steady stream of audio blocks, and no radio. Xcode
wrote the capabilities into the Mac files of this project, so the iOS target needs
its own entitlements file and `UIBackgroundModes` entry.

- After joining, a blue indicator shows. A tap opens the system bubble with the talk button.
- Transmitting from the bubble worked with the app in the background (`source=1`).
- The session became active after about 100 ms without own audio, and 620 to 660 ms with it.
  The microphone delivered 115 to 176 ms later, so about 0.75 s in all with reception on.
- **The output stops:** when the system takes over the session, the output stops and stays
  silent, also after the transmission. Starting it again when the session activates and
  deactivates, and activating the session again afterwards, worked in the background, and
  the tone was heard throughout.
- The output stood still for about 0.7 s at the start and 1 s at the end, so reception needs
  the buffer of [ADR-0043](0043-pause-other-audio.md). The test build discarded what waited,
  which the app must not do.
- A very short tap ends before the microphone has started, which then fails. This has to be
  caught without a message.

**Not tested:** the behaviour with the screen really locked, Face ID, whether the button works
by tap or by hold, the system sounds, music in other apps, and a real radio over Bluetooth.

**Open questions:** whether App Review accepts the push capability without a push server,
and whether Apple requires the framework for such apps from iOS 26, as Zello reports. The
framework expects received audio to arrive through pushes, and the radio's comes over
Bluetooth. This worked in the test, but Apple does not describe it.

## Plan, if taken up

- A setting *PTT on lock screen*, off by default, on iPhone and iPad only, as the system
  indicator stays while the channel is joined.
- With it on, the app joins the channel when connecting, and leaves it when disconnecting.
- `BEGIN` waits for the session, then starts the microphone and keys the radio. `END` stops,
  activates the session and starts the output again, without discarding audio.
- The PTT button of the app goes through the framework too, so that there is one way to
  transmit and one owner of the session.
- Frequency limits, FreeDV and the runaway timeout stay as they are. The access tone
  ([ADR-0045](0045-repeater-access-tone.md)) keeps its own way.
- A thin adapter hides the framework, and `OtherAudioController` has to leave the session to
  the system during a transmission.
- A first test should cover what is listed as not tested above.

**Possible extra:** Apple allows a transmission after a characteristic change of a Bluetooth
device, so a button on the radio could key it while locked, if the hardware offers one.
Wired headsets and CarPlay trigger it through their play and pause control.

## Consequences

- Until then, the app transmits only while it is on screen, or with sticky PTT started there.
- Audio work should keep the session and the microphone start behind one owner, so that the
  framework could take them over.
