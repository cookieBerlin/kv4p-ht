# ADR-0043: Pause other audio

- **Status:** Proposed
- **Date:** 2026-11-04

## Context

Music and podcasts of other apps play on top of a received call. Android asks for
transient audio focus, so other apps get quieter. On iOS, `AVAudioSession` decides this
through category options that take effect when the session goes active
([ADR-0030](0030-ios-audio-session.md) sets `mixWithOthers`).

A test build on an iPhone measured the options with Apple Music and Overcast, unlocked
and locked:

| Tried | Result |
|---|---|
| New options without deactivating, unlocked | Other apps never get their sound back |
| New options without deactivating, locked | iOS refuses with `cannotInterruptOthers` |
| Deactivating first, unlocked and locked | Works, the audio output stops for each switch |
| Active again 80 ms after handing back | A podcast never returns |
| Inactive for 2 s after handing back | A podcast returns after about 1.15 s, and stays when the session is active again |
| `interruptSpokenAudioAndMixWithOthers` with `duckOthers` | Podcasts pause, music gets quieter |
| Non-mixable session | Not allowed locked, unless the app is the Now Playing app |

The output stopped for 0.4 to 0.6 s to lower music, about 1 s to pause a podcast, and up
to 1 s to hand back. No buffered audio was lost with a large enough buffer. The microphone
cannot start while locked (`cannotStartRecording`), and started in about 0.1 s after
unlocking.

## Decision

- **`OtherAudioController`** (KV4PRadio) decides when to switch; `AudioSession` carries it
  out. While the radio is busy and another app plays, it deactivates the session and
  activates it with the options of the chosen mode. After the set time without a signal
  it deactivates with `notifyOthersOnDeactivation`, waits 2 s and activates the session as
  mixable again.
- **Busy** means transmitting with PTT, or an open squelch unless the squelch is 0, which
  is always open. Beacons and APRS replies do not count. Received packets do, as the app
  cannot tell them from voice.
- **No lost audio:** received audio keeps arriving during a switch, so `JitterBuffer` holds
  about 2 s while `isHolding`. It comes late rather than not at all. When the squelch has
  been closed for as long as the audio that waited, the silence behind it is discarded and
  the normal latency returns. Without a switch, the limit stays as it was.
- **PTT waits** for the switch before the microphone opens, as music from the speaker
  would go on air. While nothing else plays there is no switch, and PTT stays instant. A
  transmission never switches back, also with sticky PTT.
- **A signal during the wait** lowers other apps at once, also if the other app has not
  returned yet, so that it does not return into the signal.
- **Settings:** *Pause podcasts, lower music* (default), *Lower all* and *Keep playing*,
  and the time before other apps return. They stay on the device, as an iPhone may need
  them differently from an iPad. *Lower all* exists as a podcast app decides itself
  whether it returns.
- **No Now Playing app:** it would take over the lock screen controls from the media apps.

## Consequences

- With other audio playing, a received call starts up to a second late, and so does PTT.
- Whether a podcast app returns is its own decision.
- Session and microphone start stay in one place, so that milestone 3.5e can hand them to
  Apple's Push to Talk framework.
- The Mac has no audio session. It gets its own step, through AppleScript, in another
  change.
- Hardware test HW-25 covers the real radio over Bluetooth and Bluetooth headsets, which
  the test build did not use.
