# ADR-0050: Draggable squelch mark

- **Status:** Proposed
- **Date:** 2026-11-04

## Context

The S-meter shows the squelch level as a mark, but changing it takes a way through the
settings, away from the signal that the change is meant for. The header of an iPhone has
no room for another control, and it is touched often on the way to something else.

## Decision

- **The S-meter itself is the control.** The bars are the grip, so the mark need not be
  hit exactly, and it jumps to the finger or the pointer.
- **On a touch screen a hold of 0.3 s comes first,** confirmed by a vibration. A touch or
  a swipe that passes by changes nothing. The Mac has no such touches and drags directly.
- **The mark is a line with a small filled arrow above and below it,** pointing at the
  line. They grow while the mark is held, which also shows on a Mac, where nothing vibrates.
- **The mark rests on the levels 0 to 8,** with a light vibration for each. The level
  stands to the right of the bars while dragging, where the finger does not cover it.
- **The value goes to the radio on release,** so that a drag across the levels does not
  send every step. A cancelled drag changes nothing.
- **The squelch is locked while transmitting and during a scan,** on the S-meter, in the
  settings and for VoiceOver: a drag with the PTT finger must not change it, and a scan
  works with its own squelch and restores the one set before. A lock that begins during a
  drag ends the drag.
- **Without a radio there is no mark,** and so nothing to drag.
- **VoiceOver** reaches the same levels through the adjustable action of the S-meter.
- **The stepper in the settings stays** as a precise way to the same value.

## Consequences

- A squelch can be set by eye on a signal, with a look at the meter.
- The S-meter's text keeps a fixed width, slightly wider than before, as the bars must
  not move under the finger.
- A click on the bars on the Mac changes the squelch at once.
