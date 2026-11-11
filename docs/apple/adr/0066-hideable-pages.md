# ADR-0066: Pages that can be switched off

- **Status:** Proposed
- **Date:** 2026-11-11

## Context

Milestone 5.2 adds a map as a page of its own. With it, the app has five pages, and not everyone needs
all of them: a user who only talks over repeaters has no use for APRS. The app should be able to stay
simple. As a first step, before the map, APRS can be switched off; the map gets its own switch when it
comes (5.2b).

## Decision

- **A settings page *Pages*,** after *Station*, with one switch per part of the app that can go. In 5.2a
  that is **APRS**; the switch for the map comes with the map, so that no switch does nothing.
- **On by default,** so that nothing changes for anyone who does not look for it.
- **It stays on this device.** Settings sync (ADR-0051) leaves it out, as a phone may want less than a Mac.
- **APRS off is APRS gone as a whole, not only out of sight.** A beacon in the background, an
  acknowledgement or a digipeated packet that the app sends while nothing of APRS is on screen, and that
  cannot be switched off there, would be confusing and unwelcome on air. Off, the app
  - receives no packets, from the radio or APRS-IS, and acknowledges none;
  - sends no beacons, messages or retries of them, and digipeats nothing;
  - ends the APRS-IS connection and the background session of the beacon (ADR-0056);
  - opens no chat from a notification tapped from before.
- **The other APRS settings stay as they are,** such as the beacon, the iGate or the feed, and apply again
  when APRS is on. The packets in memory and in the store (ADR-0057) stay as well; nothing is deleted.
- **What goes from the screen:** the pages *Packets* and *Chats* of a phone, the APRS side of a wide window,
  where the memories then take the whole width, and the APRS page of the settings. A phone that showed an
  APRS page last starts with the memories.

## Consequences

- One switch in the model guards every way in and out of APRS, so a new one must check it as well.
- A message that waits for its acknowledgement while APRS goes off is retried only after APRS is on again.
- The map of 5.2b adds its switch to the same page, and its APRS layer goes with APRS.
