# ADR-0045: Repeater access tone

- **Status:** Proposed
- **Date:** 2026-11-04

## Context

Some repeaters open only on a short audio tone. The Android app has no function for this.
The tone has to arrive after the transmitter has really started, as it would be lost before
that, and it must not be mistaken for a transmission with the microphone open.

## Decision

- **`RadioController.sendAccessTone`** keys the radio and sends TX audio that comes from
  `AccessTone` instead of the microphone: silence until the radio reports `TX_ACTIVE`, the
  set wait in silence, the tone, then the transmitter stops by itself. It gives up after
  2 s without that report. The audio stays paced by the clock, like the microphone.
- **A held button:** releasing stops at once with a message that the repeater may not have
  opened. Sticky PTT has no effect on it.
- **The level is half of full scale on air,** for now. The microphone gain does not apply.
  Hardware test HW-28 checks the deviation per tone. A 5 ms ramp at both ends avoids a
  click, which would splatter on air.
- **On the device it is 2 % of full scale,** and the volume of the app applies too. This
  level was found by ear on an iPhone, where half of full scale was unpleasantly loud.
- **On the device:** the tone skips the fade-in of `RXAudioPlayer`, as that hides a transient
  of the radio that a tone made here does not have.
- **Settings:** tone (off by default), length and wait. A memory can have its own tone,
  also off, and length, or follow the settings. Both are optional fields of the stored
  memory, so existing memories follow the settings without a migration step. The wait
  belongs to the radio's timing, not to a repeater, so it has no field in the memory.
- **Other apps are left alone** ([ADR-0043](0043-pause-other-audio.md), [ADR-0044](0044-mute-other-apps-on-the-mac.md)):
  the microphone stays closed, so nothing of them can go on air, and a switch would delay
  the tone by up to a second.
- **The button** shows with a tone chosen, a connected radio, the microphone permission and
  analog voice, next to PTT on the memories page. Only here the iPhone vibrates all the
  time, as the finger has to stay.

## Consequences

- The last moments of the tone can be lost if the radio stops before its buffer has played
  out. HW-28 notes this.
- Milestone 3.6 has to hide the button in listen-only mode.
