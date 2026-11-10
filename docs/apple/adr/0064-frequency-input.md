# ADR-0064: Frequency input

- **Status:** Proposed
- **Date:** 2026-11-10

## Context

Until now the frequency at the top was a text field only. It is tuned with Return and normalised like the Android app
(`1467` → 146.7 MHz). Changing the frequency by a few channels meant typing it again. The field took no comma, although
many languages write one, and the memory form showed and read frequencies with a point only.

Facts that bound the choice:

- **Raster:** FM channels lie on a raster of 12.5 kHz (narrow) or 25 kHz (wide), matching the bandwidth of the radio.
  Stations a little off the raster exist.
- **Precision:** the radio takes the frequency as a 32-bit float in MHz. That is only close to a frequency (about 15 Hz
  at 146 MHz), and the app shows four decimals, down to 100 Hz.
- **Desired state:** every change goes to the radio in order ([protocol specification](../03-protocol-spec.md)). The
  `DesiredStateController` is pinned by golden test vectors and stays as it is. Until the radio confirms a state, its
  reports still carry the frequency it had before.
- **Platforms:** the Mac has a pointer, a scroll wheel or a trackpad and a keyboard. iPhone and iPad have touch, and no
  scroll events.

## Decision

- **Stepping rule, in whole Hz.**
  - A float frequency is rounded to 50 Hz first, which keeps half of 12.5 kHz.
  - A digit at or above the raster steps by its value and snaps to the nearest multiple of the raster. Halfway, it
    snaps in the direction of the step.
  - A lower digit steps from multiple to multiple of the raster. Off the raster, the first step goes to the next
    multiple in that direction.
  - An exact step takes the digit as it is and does not snap, for a station off the raster.
  - A step carries over (145.995 + 10 kHz = 146.005), is clamped to the limits of the radio, and changes nothing at a
    limit.
- **Tuning.**
  - A step is blocked while transmitting.
  - A step tunes at once and, like any tune, ends a scan.
  - While the radio has not confirmed the step before, only the latest step waits, and a newer one replaces it. It is
    sent once the radio is in sync.
  - Until the controller shows a frequency it was asked for, older snapshots do not replace the shown one.
  - A report of the radio replaces the shown frequency only when it is the frequency the app wants, or when the radio
    is in sync. A report from before the radio had the step therefore keeps the shown frequency.
- **Mac.**
  - The digit under the pointer is highlighted, and the scroll wheel steps it.
  - A local scroll-wheel monitor runs only while the pointer is over the frequency, so the window does not scroll.
  - A scroll wheel steps once per notch. A trackpad's scroll deltas are gathered and step once per 12 points, and a
    change of direction starts again.
  - In the field, ↑ and ↓ step the digit before the cursor. At the start of the field, or after the separator, they
    step the digit after it. The cursor stays where it was.
  - ⌥ steps by the digit exactly.
  - The digit under the pointer follows from the x position: the font is monospaced.
- **iPhone and iPad.**
  - A vertical swipe on a digit steps it, once per 24 points. Up is higher.
  - A hold of 0.4 s before the swipe steps by the digit exactly. A sideways swipe stays with the pages.
  - **−** and **+** beside the frequency step by the raster and repeat while held.
- **VoiceOver:** the field is adjustable and steps by the raster.
- **No band in the header:** the steps need room beside the frequency, above all on an iPhone, and the frequency
  already tells the band. The radio module stays in the firmware line of the settings. This amends
  [ADR-0040](0040-screen-layout.md).
- **Decimal separator.**
  - The frequencies the user sees take the separator of their language: the field, the lists, the beacon frequency, the
    memory form and the messages about frequencies and limits.
  - The log, the import keys and the storage stay with a point.
  - An entered frequency takes a comma or a point.
- **Number fields.**
  - A field for decimal numbers takes digits and at most one separator, a comma or a point. A field for whole numbers,
    such as the offset in kHz, takes none.
  - On iPhone and iPad they bring a number keyboard with a **Done** key in the keyboard's toolbar. For the frequency,
    **Done** tunes. These fields are not at the bottom of the screen, so the toolbar does not cover them.

## Consequences

- Tuning by a few channels takes a scroll, a key or a tap instead of typing.
- Fast steps do not queue up behind a slow Bluetooth connection: the radio gets the latest frequency only.
- The frequency the user sees can lead the radio briefly, until the radio confirms the step.
- The stepping rule, the digit under the pointer or cursor, the number filter and the gathering of the scroll deltas
  live in `KV4PRadio` and are fully tested. Only the gestures, the key presses and the scroll monitor are app code,
  covered by a UI test on each platform.
- A hardware test checks fast stepping on the real radio, receiving only.
